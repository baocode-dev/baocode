// Ported from CLIProxyAPI's
// internal/translator/openai/claude/openai_claude_response_test.go and
// openai_claude_compat_test.go (MIT License; see
// lib/models/proxy/translate/NOTICE.md).

import 'dart:convert';

import 'package:baocode/models/proxy/translate/json_value.dart';
import 'package:baocode/models/proxy/translate/openai_chat_request.dart';
import 'package:baocode/models/proxy/translate/openai_chat_response.dart';
import 'package:flutter_test/flutter_test.dart';

typedef SseEvent = ({String type, JsonValue payload});

/// Feeds [chunks] through one translator, then `[DONE]`, and returns the
/// events it wrote.
List<SseEvent> runStream(String originalRequest, List<String> chunks) {
  final translator = OpenAIChatResponseTranslator(originalRequest);
  final emitted = [
    for (final chunk in chunks) ...translator.convert('data: $chunk'),
    ...translator.convert('data: [DONE]'),
  ];
  return [for (final raw in emitted) ?parseEvent(raw)];
}

SseEvent? parseEvent(String raw) {
  if (!raw.startsWith('event: ')) return null;
  final nl = raw.indexOf('\n');
  if (nl < 0) return null;
  final rest = raw.substring(nl + 1);
  if (!rest.startsWith('data: ')) return null;
  return (
    type: raw.substring(7, nl),
    payload: JsonValue.parse(rest.substring(6).trimRight()),
  );
}

int countByType(List<SseEvent> events, String type) =>
    events.where((e) => e.type == type).length;

List<SseEvent> toolUseStarts(List<SseEvent> events) => [
  for (final e in events)
    if (e.type == 'content_block_start' &&
        e.payload.get('content_block.type').string == 'tool_use')
      e,
];

List<int> blockIndices(List<SseEvent> events) => [
  for (final e in events)
    if (e.type == 'content_block_start') e.payload.get('index').integer,
];

String lastStopReason(List<SseEvent> events) {
  for (final e in events.reversed) {
    if (e.type == 'message_delta') {
      return e.payload.get('delta.stop_reason').string;
    }
  }
  return '';
}

List<SseEvent> deltasOfType(List<SseEvent> events, String type) => [
  for (final e in events)
    if (e.type == 'content_block_delta' &&
        e.payload.get('delta.type').string == type)
      e,
];

List<String> thinkingDeltas(List<SseEvent> events) => [
  for (final e in deltasOfType(events, 'thinking_delta'))
    e.payload.get('delta.thinking').string,
];

SseEvent firstOfType(List<SseEvent> events, String type) =>
    events.firstWhere((e) => e.type == type);

/// Blocks open and close one at a time, and all close.
void expectSequentialContentBlocks(List<SseEvent> events) {
  var active = -1;
  for (final e in events) {
    final index = e.payload.get('index').integer;
    switch (e.type) {
      case 'content_block_start':
        expect(active, -1, reason: 'start $index while $active open');
        active = index;
      case 'content_block_delta' || 'content_block_stop':
        expect(active, index, reason: '${e.type} $index, open $active');
        if (e.type == 'content_block_stop') active = -1;
    }
  }
  expect(active, -1, reason: 'stream ended with block $active open');
}

const streamReq = '{"stream":true}';

void main() {
  test('late usage-only chunk does not emit after message_stop', () {
    final events = runStream(streamReq, [
      '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]}',
      '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"content":"hello"},"finish_reason":null}]}',
      '{"id":"c1","model":"m","choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1}}',
      '{"id":"c1","model":"m","choices":[],"usage":{"prompt_tokens":1,"completion_tokens":1}}',
    ]);
    expect(countByType(events, 'message_delta'), 1);
    expect(countByType(events, 'message_stop'), 1);
    expect(events.last.type, 'message_stop');
  });

  test('stream ignores null tool name delta', () {
    final translator = OpenAIChatResponseTranslator(streamReq);
    final first = translator
        .convert(
          'data: {"id":"chatcmpl_1","model":"test-model","created":1,"choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"read_file","arguments":""}}]},"finish_reason":null}]}',
        )
        .join();
    expect(first, contains('"name":"read_file"'));
    final second = translator
        .convert(
          'data: {"id":"chatcmpl_1","model":"test-model","created":1,"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"name":null,"arguments":"{\\"path\\":\\"/tmp/a\\"}"}}]},"finish_reason":null}]}',
        )
        .join();
    expect(second, isNot(contains('content_block_start')));
    expect(second, isNot(contains('"name":""')));
  });

  group('tool names', () {
    test('empty name throughout gets a synthetic name', () {
      final events = runStream(streamReq, [
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_a","function":{"name":"","arguments":""}}]}}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"name":"","arguments":"{\\"x\\":1}"}}]}}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}',
      ]);
      final starts = toolUseStarts(events);
      expect(starts, hasLength(1));
      expect(starts[0].payload.get('content_block.name').string, 'tool_0');
      expect(starts[0].payload.get('content_block.id').string, 'call_a');
      expect(countByType(events, 'content_block_delta'), 1);
      expect(countByType(events, 'content_block_stop'), 1);
      expect(lastStopReason(events), 'tool_use');
    });

    test('null name', () {
      final events = runStream(streamReq, [
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_a","function":{"name":null,"arguments":""}}]}}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}',
      ]);
      final starts = toolUseStarts(events);
      expect(starts, hasLength(1));
      expect(starts[0].payload.get('content_block.name').string, 'tool_0');
      expect(starts[0].payload.get('content_block.id').string, 'call_a');
      expect(countByType(events, 'content_block_stop'), 1);
      expect(lastStopReason(events), 'tool_use');
    });

    test('non-string name', () {
      final events = runStream(streamReq, [
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_a","function":{"name":123,"arguments":""}}]}}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}',
      ]);
      final starts = toolUseStarts(events);
      expect(starts, hasLength(1));
      expect(starts[0].payload.get('content_block.name').string, 'tool_0');
    });

    test('repeated name', () {
      final events = runStream(streamReq, [
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_a","function":{"name":"do_it","arguments":""}}]}}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"name":"do_it","arguments":"{\\"x\\""}}]}}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"name":"do_it","arguments":":1}"}}]}}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}',
      ]);
      final starts = toolUseStarts(events);
      expect(starts, hasLength(1));
      expect(starts[0].payload.get('content_block.name').string, 'do_it');
      expect(countByType(events, 'content_block_stop'), 1);
    });

    test('mixed empty name and valid', () {
      final events = runStream(streamReq, [
        '''{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[
          {"index":0,"id":"call_empty","function":{"name":"","arguments":""}},
          {"index":1,"id":"call_real","function":{"name":"do_it","arguments":""}}
        ]}}]}''',
        '''{"id":"c1","model":"m","choices":[{"index":0,"delta":{"tool_calls":[
          {"index":1,"function":{"arguments":"{}"}}
        ]}}]}''',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}',
      ]);
      final starts = toolUseStarts(events);
      expect(starts, hasLength(2));
      // The named one mid-stream, the nameless one at the finish.
      expect(starts[0].payload.get('content_block.name').string, 'do_it');
      expect(starts[1].payload.get('content_block.name').string, 'tool_0');
      expect(countByType(events, 'content_block_stop'), 2);
      expect(blockIndices(events).take(2), [0, 1]);
    });

    test('empty name without signal is suppressed', () {
      final events = runStream(streamReq, [
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"function":{"name":"","arguments":""}}]}}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}',
      ]);
      expect(toolUseStarts(events), isEmpty);
      expect(lastStopReason(events), isNot('tool_use'));
    });

    test('stop reason with mixed empty name and valid', () {
      final events = runStream(streamReq, [
        '''{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[
          {"index":0,"id":"call_empty","function":{"name":"","arguments":""}},
          {"index":1,"id":"call_real","function":{"name":"do_it","arguments":"{}"}}
        ]}}]}''',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}',
      ]);
      expect(lastStopReason(events), 'tool_use');
      expect(toolUseStarts(events), hasLength(2));
    });

    test('empty name, arguments only, no id', () {
      final events = runStream(streamReq, [
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"function":{"name":"","arguments":"{\\"q\\":\\"x\\"}"}}]}}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}',
      ]);
      final starts = toolUseStarts(events);
      expect(starts, hasLength(1));
      expect(starts[0].payload.get('content_block.name').string, 'tool_0');
      expect(
        starts[0].payload.get('content_block.id').string,
        startsWith('toolu_'),
      );
      expect(lastStopReason(events), 'tool_use');
    });
  });

  group('tool ids', () {
    test('empty id defers the start', () {
      final events = runStream(streamReq, [
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"","function":{"name":"do_it","arguments":""}}]}}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_real","function":{"arguments":"{}"}}]}}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}',
      ]);
      final starts = toolUseStarts(events);
      expect(starts, hasLength(1));
      expect(starts[0].payload.get('content_block.id').string, 'call_real');
    });

    test('id in a delta without function', () {
      final events = runStream(streamReq, [
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"function":{"name":"do_it"}}]}}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_real"}]}}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{}"}}]}}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}',
      ]);
      final starts = toolUseStarts(events);
      expect(starts, hasLength(1));
      expect(starts[0].payload.get('content_block.id').string, 'call_real');
      expect(starts[0].payload.get('content_block.name').string, 'do_it');
      expect(countByType(events, 'content_block_stop'), 1);
    });

    test('stop reason with emitted tool', () {
      final events = runStream(streamReq, [
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_a","function":{"name":"do_it","arguments":"{}"}}]}}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":1,"completion_tokens":1}}',
      ]);
      expect(lastStopReason(events), 'tool_use');
    });

    test('stop reason when the id never arrives', () {
      final events = runStream(streamReq, [
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"function":{"name":"do_it","arguments":""}}]}}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{}"}}]}}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}',
      ]);
      final starts = toolUseStarts(events);
      expect(starts, hasLength(1));
      expect(
        starts[0].payload.get('content_block.id').string,
        startsWith('toolu_'),
      );
      expect(starts[0].payload.get('content_block.name').string, 'do_it');
      expect(lastStopReason(events), 'tool_use');
    });

    test('belated starts follow the OpenAI tool index order', () {
      final events = runStream(streamReq, [
        '''{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[
          {"index":2,"function":{"name":"third_tool","arguments":"{}"}},
          {"index":0,"function":{"name":"first_tool","arguments":"{}"}},
          {"index":1,"function":{"name":"second_tool","arguments":"{}"}}
        ]}}]}''',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}',
      ]);
      final starts = toolUseStarts(events);
      expect(starts, hasLength(3));
      for (final (i, name) in [
        'first_tool',
        'second_tool',
        'third_tool',
      ].indexed) {
        expect(starts[i].payload.get('content_block.name').string, name);
        expect(starts[i].payload.get('index').integer, i);
      }
    });

    test('late id after finalization emits nothing after message_stop', () {
      final events = runStream(streamReq, [
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"function":{"name":"do_it"}}]}}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":1,"completion_tokens":1}}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_late"}]}}]}',
      ]);
      expect(toolUseStarts(events), hasLength(1));
      final stop = events.indexWhere((e) => e.type == 'message_stop');
      for (final e in events.skip(stop + 1)) {
        expect(e.type, isNot(startsWith('content_block_')));
      }
    });
  });

  group('omitted finish reason', () {
    test('tool call: message_delta on [DONE]', () {
      final events = runStream(streamReq, [
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_1","function":{"name":"get_weather","arguments":"{\\"loc\\":\\"Paris\\"}"}}]},"finish_reason":null}]}',
      ]);
      expect(countByType(events, 'message_delta'), 1);
      expect(lastStopReason(events), 'tool_use');
      expect(countByType(events, 'message_stop'), 1);
      expect(events[events.length - 2].type, 'message_delta');
      expect(events.last.type, 'message_stop');
    });

    test('text: end_turn on [DONE]', () {
      final events = runStream(streamReq, [
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","content":"hello world"},"finish_reason":null}]}',
      ]);
      expect(countByType(events, 'message_delta'), 1);
      expect(lastStopReason(events), 'end_turn');
      expect(countByType(events, 'message_stop'), 1);
    });

    test('usage without finish reason emits message_delta', () {
      final events = runStream(streamReq, [
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_1","function":{"name":"get_weather","arguments":"{\\"loc\\":\\"Paris\\"}"}}]},"finish_reason":null}]}',
        '{"id":"c1","model":"m","choices":[],"usage":{"prompt_tokens":10,"completion_tokens":5}}',
      ]);
      expect(countByType(events, 'message_delta'), 1);
      expect(lastStopReason(events), 'tool_use');
      final delta = firstOfType(events, 'message_delta').payload;
      expect(delta.get('usage.input_tokens').integer, 10);
      expect(delta.get('usage.output_tokens').integer, 5);
      expect(countByType(events, 'message_stop'), 1);
    });
  });

  group('per-chunk usage preserves tool arguments', () {
    for (final finish in ['"tool_calls"', 'null']) {
      test('finish_reason $finish', () {
        final events = runStream(streamReq, [
          '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"Skill","arguments":""}}]},"finish_reason":null}],"usage":{"prompt_tokens":191,"completion_tokens":5}}',
          '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"function":{"arguments":"{\\"skill\\": \\"stop-s"}}]},"finish_reason":null}],"usage":{"prompt_tokens":191,"completion_tokens":10}}',
          '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"function":{"arguments":"lop\\"}"}}]},"finish_reason":$finish}],"usage":{"prompt_tokens":191,"completion_tokens":15}}',
        ]);
        final starts = toolUseStarts(events);
        expect(starts, hasLength(1));
        expect(starts[0].payload.get('content_block.name').string, 'Skill');
        expect(starts[0].payload.get('content_block.id').string, 'call_1');
        final merged = deltasOfType(
          events,
          'input_json_delta',
        ).map((d) => d.payload.get('delta.partial_json').string).join();
        expect(merged, '{"skill": "stop-slop"}');
        expect(countByType(events, 'message_delta'), 1);
        expect(lastStopReason(events), 'tool_use');
        expect(countByType(events, 'message_stop'), 1);
        final delta = firstOfType(events, 'message_delta').payload;
        expect(delta.get('usage.input_tokens').integer, 191);
        expect(delta.get('usage.output_tokens').integer, 15);
      });
    }
  });

  test('omitted tool call index preserves parallel calls', () {
    final events = runStream(streamReq, [
      '''{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[
        {"id":"call_weather","type":"function","function":{"name":"get_weather","arguments":"{\\"city\\":\\"Paris\\"}"}},
        {"id":"call_time","type":"function","function":{"name":"get_time","arguments":"{\\"tz\\":\\"UTC\\"}"}}
      ]},"finish_reason":"tool_calls"}]}''',
    ]);
    final starts = toolUseStarts(events);
    expect(starts, hasLength(2));
    expect(starts[0].payload.get('content_block.id').string, 'call_weather');
    expect(starts[0].payload.get('content_block.name').string, 'get_weather');
    expect(starts[1].payload.get('content_block.id').string, 'call_time');
    expect(starts[1].payload.get('content_block.name').string, 'get_time');
    final deltas = deltasOfType(events, 'input_json_delta');
    expect(deltas, hasLength(2));
    final first = JsonValue.parse(
      deltas[0].payload.get('delta.partial_json').string,
    );
    final second = JsonValue.parse(
      deltas[1].payload.get('delta.partial_json').string,
    );
    expect(first.get('city').string, 'Paris');
    expect(second.get('tz').string, 'UTC');
    expect(countByType(events, 'content_block_stop'), 2);
    expect(lastStopReason(events), 'tool_use');
  });

  const usageCases = [
    (
      name: 'cache_write_tokens field',
      usage: '{"prompt_tokens":1000,"completion_tokens":200,"prompt_tokens_details":{"cached_tokens":800,"cache_write_tokens":150}}',
      input: 50,
      output: 200,
      cacheRead: 800,
      cacheWrite: 150,
    ),
    (
      name: 'cache_creation_tokens alias',
      usage: '{"prompt_tokens":1000,"completion_tokens":200,"prompt_tokens_details":{"cached_tokens":800,"cache_creation_tokens":150}}',
      input: 50,
      output: 200,
      cacheRead: 800,
      cacheWrite: 150,
    ),
    (
      name: 'cached_tokens greater than prompt_tokens clamps input to zero',
      usage: '{"prompt_tokens":500,"completion_tokens":100,"prompt_tokens_details":{"cached_tokens":800,"cache_write_tokens":50}}',
      input: 0,
      output: 100,
      cacheRead: 800,
      cacheWrite: 50,
    ),
    (
      name: 'zero cache_write_tokens does not emit cache_creation_input_tokens',
      usage: '{"prompt_tokens":1000,"completion_tokens":200,"prompt_tokens_details":{"cached_tokens":800,"cache_write_tokens":0}}',
      input: 200,
      output: 200,
      cacheRead: 800,
      cacheWrite: 0,
    ),
    (
      name: 'cache_write_tokens only deducts from input',
      usage: '{"prompt_tokens":4022,"completion_tokens":462,"prompt_tokens_details":{"cached_tokens":0,"cache_write_tokens":4019}}',
      input: 3,
      output: 462,
      cacheRead: 0,
      cacheWrite: 4019,
    ),
    (
      name: 'cached and cache_write greater than prompt_tokens clamps to zero',
      usage: '{"prompt_tokens":500,"completion_tokens":100,"prompt_tokens_details":{"cached_tokens":300,"cache_write_tokens":300}}',
      input: 0,
      output: 100,
      cacheRead: 300,
      cacheWrite: 300,
    ),
  ];

  void expectUsage(
    JsonValue usage,
    ({
      String name,
      String usage,
      int input,
      int output,
      int cacheRead,
      int cacheWrite,
    })
    c,
  ) {
    expect(usage.get('input_tokens').integer, c.input);
    expect(usage.get('output_tokens').integer, c.output);
    expect(usage.get('cache_read_input_tokens').integer, c.cacheRead);
    if (c.cacheWrite == 0) {
      expect(usage.get('cache_creation_input_tokens').exists, isFalse);
    } else {
      expect(usage.get('cache_creation_input_tokens').integer, c.cacheWrite);
    }
  }

  group('streaming usage preserves cache write tokens', () {
    for (final c in usageCases) {
      test(c.name, () {
        final events = runStream(streamReq, [
          '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","content":"hello"}}]}',
          '{"id":"c1","model":"m","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}',
          '{"id":"c1","model":"m","choices":[],"usage":${c.usage}}',
        ]);
        expectUsage(
          firstOfType(events, 'message_delta').payload.get('usage'),
          c,
        );
      });
    }
  });

  group('non-streaming usage preserves cache write tokens', () {
    for (final c in usageCases) {
      test(c.name, () {
        final raw = '''{
          "id":"chatcmpl-123","object":"chat.completion","created":1677652288,"model":"gpt-5.4",
          "choices":[{"index":0,"message":{"role":"assistant","content":"Hello world"},"finish_reason":"stop"}],
          "usage":${c.usage}}''';
        const request =
            '{"model":"claude-3-5-sonnet-20241022","messages":[{"role":"user","content":"Hello"}]}';
        final out = JsonValue(
          convertOpenAIResponseToClaudeNonStream(request, raw),
        );
        expectUsage(out.get('usage'), c);
      });
    }
  });

  group('strict sequential blocks', () {
    test('content interleaved with a tool call', () {
      final events = runStream(streamReq, [
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"Bash","arguments":"{\\"command\\":"}}]},"finish_reason":null}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"content":"\\n"},"finish_reason":null}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"ls\\"}"}}]},"finish_reason":null}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}',
      ]);
      expectSequentialContentBlocks(events);
      final deltas = deltasOfType(events, 'input_json_delta');
      expect(deltas, hasLength(1));
      final args = JsonValue.parse(
        deltas[0].payload.get('delta.partial_json').string,
      );
      expect(args.get('command').string, 'ls');
    });

    test('parallel tool calls', () {
      final events = runStream(streamReq, [
        '''{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[
          {"index":0,"id":"call_1","type":"function","function":{"name":"Bash","arguments":"{\\"command\\":\\"ls\\"}"}},
          {"index":1,"id":"call_2","type":"function","function":{"name":"Read","arguments":"{\\"path\\":\\"/tmp\\"}"}}
        ]},"finish_reason":"tool_calls"}]}''',
      ]);
      expectSequentialContentBlocks(events);
      final starts = toolUseStarts(events);
      expect(starts, hasLength(2));
      expect(starts[0].payload.get('content_block.id').string, 'call_1');
      expect(starts[0].payload.get('content_block.name').string, 'Bash');
      expect(starts[1].payload.get('content_block.id').string, 'call_2');
      expect(starts[1].payload.get('content_block.name').string, 'Read');
      final deltas = deltasOfType(events, 'input_json_delta');
      expect(deltas, hasLength(2));
      String arg(SseEvent e, String key) =>
          JsonValue.parse(e.payload.get('delta.partial_json').string)
              .get(key)
              .string;
      expect(arg(deltas[0], 'command'), 'ls');
      expect(arg(deltas[1], 'path'), '/tmp');
    });

    test('interleaved text and thinking keep their order', () {
      final events = runStream(streamReq, [
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"Bash","arguments":"{\\"command\\":"}}]},"finish_reason":null}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"content":"Note A: "},"finish_reason":null}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"content":"running check"},"finish_reason":null}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"reasoning_content":"Thinking about safety"},"finish_reason":null}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"content":"Note B: done"},"finish_reason":null}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"pwd\\"}"}}]},"finish_reason":null}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}',
      ]);
      expectSequentialContentBlocks(events);
      expect(
        [
          for (final e in events)
            if (e.type == 'content_block_start')
              e.payload.get('content_block.type').string,
        ],
        ['tool_use', 'text', 'thinking', 'text'],
      );
      final tool = deltasOfType(events, 'input_json_delta').single;
      expect(
        JsonValue.parse(tool.payload.get('delta.partial_json').string)
            .get('command')
            .string,
        'pwd',
      );
      expect(
        [
          for (final e in deltasOfType(events, 'text_delta'))
            e.payload.get('delta.text').string,
        ],
        ['Note A: running check', 'Note B: done'],
      );
      expect(thinkingDeltas(events), ['Thinking about safety']);
    });
  });

  group('tool stop reasons', () {
    const truncated =
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"write_file","arguments":"{\\"path\\":\\"/tmp/test.txt\\",\\"content\\":\\"hello"}}]},"finish_reason":null}]}';
    const complete =
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"write_file","arguments":"{\\"path\\":\\"/tmp/test.txt\\"}"}}]},"finish_reason":null}]}';
    String finish(String reason, int completion) =>
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{},"finish_reason":"$reason"}],"usage":{"prompt_tokens":10,"completion_tokens":$completion}}';

    final cases = [
      (
        name: 'finish length emits max_tokens',
        chunks: [truncated, finish('length', 400)],
        want: 'max_tokens',
      ),
      (
        name: 'truncated arguments without finish reason',
        chunks: [truncated],
        want: 'max_tokens',
      ),
      (
        name: 'valid arguments with stop emit tool_use',
        chunks: [complete, finish('stop', 20)],
        want: 'tool_use',
      ),
      (
        name: 'truncated arguments with stop emit max_tokens',
        chunks: [
          '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"write_file","arguments":"{\\"path\\":\\"/tmp/test.txt\\""}}]},"finish_reason":null}]}',
          finish('stop', 20),
        ],
        want: 'max_tokens',
      ),
      (
        name: 'empty arguments with tool_calls emit tool_use',
        chunks: [
          '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"get_time","arguments":""}}]},"finish_reason":null}]}',
          finish('tool_calls', 10),
        ],
        want: 'tool_use',
      ),
      (
        name: 'whitespace-only arguments without finish reason',
        chunks: [
          '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"write_file","arguments":" \\n\\t"}}]},"finish_reason":null}]}',
        ],
        want: 'max_tokens',
      ),
      (
        name: 'content_filter with a tool call emits end_turn',
        chunks: [complete, finish('content_filter', 20)],
        want: 'end_turn',
      ),
      (
        name: 'parallel calls, one truncated',
        chunks: [
          '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"write_file","arguments":"{\\"path\\":\\"/tmp/a\\"}"}},{"index":1,"id":"call_2","type":"function","function":{"name":"write_file","arguments":"{\\"path\\":\\"/tmp/b"}}]},"finish_reason":null}]}',
        ],
        want: 'max_tokens',
      ),
      (
        name: 'multi-chunk truncated with trailing usage',
        chunks: [
          '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"write_file","arguments":"{\\"path\\":\\"/tmp/a\\","}}]},"finish_reason":null}]}',
          '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"function":{"arguments":"\\"content\\":\\"incompl"}}]},"finish_reason":null}]}',
          '{"id":"c1","model":"m","choices":[],"usage":{"prompt_tokens":10,"completion_tokens":400}}',
        ],
        want: 'max_tokens',
      ),
    ];
    for (final c in cases) {
      test(c.name, () {
        expect(lastStopReason(runStream(streamReq, c.chunks)), c.want);
      });
    }
  });

  group('reasoning', () {
    test('reasoning field emits a thinking delta', () {
      final events = runStream(streamReq, [
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"reasoning":"I am thinking","reasoning_details":[{"type":"reasoning.text","text":"I am thinking"}]},"finish_reason":null}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}',
      ]);
      expect(thinkingDeltas(events), ['I am thinking']);
    });

    test('reasoning_content still preferred', () {
      final events = runStream(streamReq, [
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"reasoning_content":"primary reasoning","reasoning":"fallback reasoning"},"finish_reason":null}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}',
      ]);
      expect(thinkingDeltas(events), ['primary reasoning']);
    });

    test('reasoning_details alone emits a thinking delta', () {
      final events = runStream(streamReq, [
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"reasoning_details":[{"type":"reasoning.text","text":"Only details thinking"}]},"finish_reason":null}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"content":"Answer"},"finish_reason":null}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}',
      ]);
      expect(thinkingDeltas(events), ['Only details thinking']);
    });

    test('empty reasoning_content falls back to reasoning', () {
      final events = runStream(streamReq, [
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"reasoning_content":"","reasoning":"fallback from empty"},"finish_reason":null}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{"reasoning_content":null,"reasoning":"fallback from null"},"finish_reason":null}]}',
        '{"id":"c1","model":"m","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}',
      ]);
      expect(thinkingDeltas(events), [
        'fallback from empty',
        'fallback from null',
      ]);
    });

    test('non-stream reasoning field emits a thinking block', () {
      const raw =
          '{"id":"chatcmpl-1","object":"chat.completion","model":"deepseek","choices":[{"index":0,"message":{"role":"assistant","content":"Done","reasoning":"Thought process"},"finish_reason":"stop"}]}';
      List<String> thinking(JsonValue out) => [
        for (final block in out.get('content').array)
          if (block.get('type').string == 'thinking')
            block.get('thinking').string,
      ];

      final out = JsonValue(convertOpenAIResponseToClaudeNonStream(null, raw));
      expect(thinking(out), ['Thought process']);

      final emitted = OpenAIChatResponseTranslator('{"stream":false}')
          .convert('data: $raw');
      expect(emitted, isNotEmpty);
      expect(thinking(JsonValue.parse(emitted[0])), ['Thought process']);
    });
  });

  group('extractOpenAIUsage', () {
    const cases = [
      (name: 'absent usage', raw: '', want: (0, 0, 0, 0)),
      (name: 'null usage', raw: 'null', want: (0, 0, 0, 0)),
      (
        name: 'no cache details',
        raw: '{"prompt_tokens":100,"completion_tokens":50}',
        want: (100, 50, 0, 0),
      ),
      (
        name: 'deducts cached_tokens only',
        raw: '{"prompt_tokens":100,"completion_tokens":50,"prompt_tokens_details":{"cached_tokens":30}}',
        want: (70, 50, 30, 0),
      ),
      (
        name: 'deducts cache_write_tokens only',
        raw: '{"prompt_tokens":4022,"completion_tokens":462,"prompt_tokens_details":{"cache_write_tokens":4019}}',
        want: (3, 462, 0, 4019),
      ),
      (
        name: 'deducts cache_creation_tokens alias only',
        raw: '{"prompt_tokens":4022,"completion_tokens":462,"prompt_tokens_details":{"cache_creation_tokens":4019}}',
        want: (3, 462, 0, 4019),
      ),
      (
        name: 'deducts both',
        raw: '{"prompt_tokens":1000,"completion_tokens":200,"prompt_tokens_details":{"cached_tokens":800,"cache_write_tokens":150}}',
        want: (50, 200, 800, 150),
      ),
      (
        name: 'clamps input to zero when cache exceeds prompt',
        raw: '{"prompt_tokens":500,"completion_tokens":100,"prompt_tokens_details":{"cached_tokens":300,"cache_write_tokens":300}}',
        want: (0, 100, 300, 300),
      ),
      (
        name: 'negative cache numbers leave input alone',
        raw: '{"prompt_tokens":100,"completion_tokens":50,"prompt_tokens_details":{"cached_tokens":-10,"cache_write_tokens":-5}}',
        want: (100, 50, -10, 0),
      ),
      (
        name: 'clamps negative prompt_tokens to zero',
        raw: '{"prompt_tokens":-10,"completion_tokens":50}',
        want: (0, 50, 0, 0),
      ),
      (
        name: 'negative cache_write_tokens falls back to cache_creation_tokens',
        raw: '{"prompt_tokens":100,"completion_tokens":50,"prompt_tokens_details":{"cache_write_tokens":-1,"cache_creation_tokens":40}}',
        want: (60, 50, 0, 40),
      ),
      (
        name: 'huge counts do not overflow',
        raw: '{"prompt_tokens":100,"completion_tokens":50,"prompt_tokens_details":{"cached_tokens":9223372036854775800,"cache_write_tokens":100}}',
        want: (0, 50, 9223372036854775800, 100),
      ),
    ];
    for (final c in cases) {
      test(c.name, () {
        final usage = c.raw.isEmpty
            ? JsonValue.missing
            : JsonValue.parse(c.raw);
        expect(extractOpenAIUsage(usage), c.want);
      });
    }
  });

  // openai_claude_compat_test.go: the compat translation is
  // `preserveThinking: true`.
  group('preserveThinking', () {
    JsonValue translate(String payload, {bool preserve = true}) => JsonValue(
      jsonDecode(
        jsonEncode(
          convertClaudeRequestToOpenAI(
            'deepseek-v4',
            payload,
            false,
            preserveThinking: preserve,
          ),
        ),
      ),
    );

    test('keeps empty-signature thinking', () {
      const payload =
          '{"messages":[{"role":"assistant","content":[{"type":"thinking","thinking":"reason","signature":""}]}]}';
      expect(
        translate(
          payload,
          preserve: false,
        ).get('messages.0.reasoning_content').exists,
        isFalse,
      );
      expect(
        translate(payload).get('messages.0.reasoning_content').string,
        'reason',
      );
    });

    test('keeps thinking alongside tool calls', () {
      final assistant = translate(
        '{"messages":[{"role":"assistant","content":[{"type":"thinking","thinking":"reason","signature":""},{"type":"text","text":"Reading files."},{"type":"tool_use","id":"call_1","name":"Read","input":{"path":"main.go"}}]}]}',
      ).get('messages.0');
      expect(assistant.get('reasoning_content').string, 'reason');
      expect(assistant.get('tool_calls').exists, isTrue);
    });

    test('adds no reasoning without thinking', () {
      final assistant = translate(
        '{"messages":[{"role":"assistant","content":[{"type":"tool_use","id":"call_1","name":"Read","input":{}}]}]}',
      ).get('messages.0');
      expect(assistant.get('reasoning_content').exists, isFalse);
      expect(assistant.get('tool_calls').exists, isTrue);
    });

    test('keeps thinking with an incompatible signature', () {
      final assistant = translate(
        '{"messages":[{"role":"assistant","content":[{"type":"thinking","thinking":"reason","signature":"claude#opaque"},{"type":"tool_use","id":"call_1","name":"Read","input":{}}]}]}',
      ).get('messages.0');
      expect(assistant.get('reasoning_content').string, 'reason');
      expect(assistant.get('tool_calls').exists, isTrue);
    });

    test('default adds no reasoning for tool calls', () {
      expect(
        translate(
          '{"messages":[{"role":"assistant","content":[{"type":"tool_use","id":"call_1","name":"Read","input":{}}]}]}',
          preserve: false,
        ).get('messages.0.reasoning_content').exists,
        isFalse,
      );
    });
  });

  // Not in the Go tests: a whole tool round trip, Claude request out and
  // OpenAI stream back.
  test('tool round trip', () {
    const request = '''{"model":"claude","stream":true,
      "tools":[{"name":"Read","description":"read","input_schema":{"type":"object","properties":{"path":{"type":"string"}}}}],
      "messages":[
        {"role":"user","content":"read it"},
        {"role":"assistant","content":[{"type":"tool_use","id":"call_9","name":"Read","input":{"path":"a"}}]},
        {"role":"user","content":[{"type":"tool_result","tool_use_id":"call_9","content":"file body"}]}
      ]}''';
    final out = JsonValue(convertClaudeRequestToOpenAI('gpt', request, true));
    expect(out.get('tools.0.function.name').string, 'Read');
    expect(out.get('messages.1.tool_calls.0.id').string, 'call_9');
    expect(out.get('messages.2.role').string, 'tool');
    expect(out.get('messages.2.tool_call_id').string, 'call_9');

    final events = runStream(request, [
      '{"id":"c2","model":"gpt","choices":[{"index":0,"delta":{"role":"assistant","content":"Done: "}}]}',
      '{"id":"c2","model":"gpt","choices":[{"index":0,"delta":{"content":"file body"},"finish_reason":"stop"}],"usage":{"prompt_tokens":12,"completion_tokens":3}}',
    ]);
    expectSequentialContentBlocks(events);
    expect(events.first.type, 'message_start');
    expect(events.first.payload.get('message.id').string, 'c2');
    expect(
      deltasOfType(
        events,
        'text_delta',
      ).map((e) => e.payload.get('delta.text').string).join(),
      'Done: file body',
    );
    expect(lastStopReason(events), 'end_turn');
    expect(events.last.type, 'message_stop');
  });
}
