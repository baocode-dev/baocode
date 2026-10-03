// Ported from CLIProxyAPI's
// internal/translator/codex/claude/codex_claude_response_test.go and
// codex_claude_parallel_function_calls_test.go (MIT License; see
// lib/models/proxy/translate/NOTICE.md).

import 'package:baocode/models/proxy/translate/json_value.dart';
import 'package:baocode/models/proxy/translate/responses_response.dart';
import 'package:flutter_test/flutter_test.dart';

/// What [translator] writes for each of [chunks].
List<String> feed(
  ResponsesResponseTranslator translator,
  List<String> chunks,
) => [for (final chunk in chunks) translator.convert(chunk)];

List<String> translate(
  List<String> chunks, {
  String request = '{"messages":[]}',
}) => feed(ResponsesResponseTranslator(request), chunks);

/// The `data:` payloads in [outputs], in order.
List<JsonValue> dataOf(List<String> outputs) => [
  for (final output in outputs)
    for (final line in output.split('\n'))
      if (line.startsWith('data: ')) JsonValue.parse(line.substring(6)),
];

JsonValue? messageDelta(List<String> outputs) =>
    dataOf(outputs)
        .where((d) => d.get('type').string == 'message_delta')
        .firstOrNull;

String? stopReason(List<String> outputs) =>
    messageDelta(outputs)?.get('delta.stop_reason').string;

JsonValue? firstPayloadForEvent(String output, String event) {
  var current = '';
  for (final line in output.split('\n')) {
    if (line.startsWith('event: ')) {
      current = line.substring(7);
    } else if (current == event && line.startsWith('data: ')) {
      return JsonValue.parse(line.substring(6));
    }
  }
  return null;
}

typedef ThinkingDigest = ({
  int starts,
  int stops,
  List<String> signatures,
  String thinking,
  String raw,
});

ThinkingDigest digestThinking(List<String> chunks) {
  final outputs = translate(chunks);
  var starts = 0;
  var stops = 0;
  final signatures = <String>[];
  final thinking = StringBuffer();
  for (final data in dataOf(outputs)) {
    switch (data.get('type').string) {
      case 'content_block_start':
        if (data.get('content_block.type').string == 'thinking') starts++;
      case 'content_block_delta':
        switch (data.get('delta.type').string) {
          case 'thinking_delta':
            thinking.write(data.get('delta.thinking').string);
          case 'signature_delta':
            signatures.add(data.get('delta.signature').string);
        }
      case 'content_block_stop':
        stops++;
    }
  }
  return (
    starts: starts,
    stops: stops,
    signatures: signatures,
    thinking: '$thinking',
    raw: outputs.join(),
  );
}

class Block {
  Block(this.index, this.type, this.id, this.name);

  final int index;
  final String type;
  final String id;
  final String name;
  String text = '';
  String arguments = '';

  @override
  String toString() => '$index $type $id $name "$text" $arguments';
}

/// The blocks in [outputs], checking that they open and close one at a
/// time with fresh indexes, all before message_delta and message_stop.
List<Block> blockLifecycle(List<String> outputs) {
  final open = <int, Block>{};
  final started = <int>{};
  final blocks = <Block>[];
  var messageState = 0;
  for (final event in dataOf(outputs)) {
    expect(
      messageState,
      isNot(2),
      reason: 'event after message_stop: ${event.raw}',
    );
    final index = event.get('index').integer;
    switch (event.get('type').string) {
      case 'content_block_start':
        expect(messageState, 0);
        expect(open, isEmpty, reason: 'start while $open open');
        expect(started.add(index), isTrue, reason: 'index $index reused');
        final block = Block(
          index,
          event.get('content_block.type').string,
          event.get('content_block.id').string,
          event.get('content_block.name').string,
        );
        open[index] = block;
        blocks.add(block);
      case 'content_block_delta':
        final block = open[index];
        expect(block, isNotNull, reason: 'delta for unopened $index');
        switch (event.get('delta.type').string) {
          case 'input_json_delta':
            block!.arguments += event.get('delta.partial_json').string;
          case 'text_delta':
            block!.text += event.get('delta.text').string;
        }
      case 'content_block_stop':
        expect(
          open.remove(index),
          isNotNull,
          reason: 'stop for unopened $index',
        );
      case 'message_delta':
        expect(open, isEmpty);
        expect(messageState, 0);
        messageState = 1;
      case 'message_stop':
        expect(open, isEmpty);
        expect(messageState, 1);
        messageState = 2;
    }
  }
  expect(open, isEmpty, reason: 'blocks left open');
  return blocks;
}

List<Block> parallelLifecycle(List<String> chunks) => blockLifecycle(
  translate(chunks, request: '{"stream":true,"tools":[{"name":"Read"}]}'),
);

void expectParallelReadCalls(List<Block> blocks) {
  expect(blocks, hasLength(2));
  const ids = ['call_a', 'call_b'];
  const arguments = ['{"file_path":"a"}', '{"file_path":"b"}'];
  for (final (i, block) in blocks.indexed) {
    expect(block.index, i);
    expect(block.type, 'tool_use');
    expect(block.name, 'Read');
    expect(block.id, ids[i]);
    expect(block.arguments, arguments[i]);
  }
}

const lookupRequest = '{"tools":[{"name":"lookup","description":"lookup"}]}';
const lookupSchemaRequest =
    '{"tools":[{"name":"lookup","input_schema":{"type":"object","properties":{}}}]}';
const webSearchRequest =
    '{"tools":[{"type":"web_search_20250305","name":"web_search"}],"messages":[{"role":"user","content":"search weather"}]}';

void main() {
  group('thinking', () {
    test('includes the signature', () {
      final data = dataOf(
        translate([
          'data: {"type":"response.created","response":{"id":"resp_123","model":"gpt-5"}}',
          'data: {"type":"response.reasoning_summary_part.added"}',
          'data: {"type":"response.reasoning_summary_text.delta","delta":"Let me think"}',
          'data: {"type":"response.reasoning_summary_part.done"}',
          'data: {"type":"response.output_item.done","item":{"type":"reasoning","encrypted_content":"enc_sig_123"}}',
        ]),
      );
      final start = data.firstWhere(
        (d) =>
            d.get('type').string == 'content_block_start' &&
            d.get('content_block.type').string == 'thinking',
      );
      expect(start.get('content_block.signature').exists, isFalse);
      final signatures = [
        for (final d in data)
          if (d.get('delta.type').string == 'signature_delta')
            d.get('delta.signature').string,
      ];
      expect(signatures, ['enc_sig_123']);
      expect(
        data.any((d) => d.get('type').string == 'content_block_stop'),
        isTrue,
      );
    });

    test('without a reasoning item has no signature', () {
      final data = dataOf(
        translate([
          'data: {"type":"response.reasoning_summary_part.added"}',
          'data: {"type":"response.reasoning_summary_text.delta","delta":"Let me think"}',
          'data: {"type":"response.reasoning_summary_part.done"}',
          'data: {"type":"response.completed","response":{"usage":{"input_tokens":1,"output_tokens":1}}}',
        ]),
      );
      final start = data.firstWhere(
        (d) => d.get('content_block.type').string == 'thinking',
      );
      expect(start.get('content_block.signature').exists, isFalse);
      expect(
        data.any(
          (d) =>
              d.get('type').string == 'content_block_stop' &&
              d.get('index').integer == 0,
        ),
        isTrue,
      );
      expect(
        data.any((d) => d.get('delta.type').string == 'signature_delta'),
        isFalse,
      );
    });

    test('keeps a single block across summary parts', () {
      final digest = digestThinking([
        'data: {"type":"response.reasoning_summary_part.added"}',
        'data: {"type":"response.reasoning_summary_text.delta","delta":"First part"}',
        'data: {"type":"response.reasoning_summary_part.done"}',
        'data: {"type":"response.reasoning_summary_part.added"}',
        'data: {"type":"response.reasoning_summary_text.delta","delta":"Second part"}',
      ]);
      expect(digest.starts, 1);
      expect(digest.stops, 0);
      expect(digest.thinking, 'First part\n\nSecond part');
    });

    test('one signature across multipart reasoning', () {
      final digest = digestThinking([
        'data: {"type":"response.output_item.added","item":{"type":"reasoning","encrypted_content":"enc_sig_multipart"}}',
        'data: {"type":"response.reasoning_summary_part.added"}',
        'data: {"type":"response.reasoning_summary_text.delta","delta":"First part"}',
        'data: {"type":"response.reasoning_summary_part.done"}',
        'data: {"type":"response.reasoning_summary_part.added"}',
        'data: {"type":"response.reasoning_summary_text.delta","delta":"Second part"}',
        'data: {"type":"response.reasoning_summary_part.done"}',
        'data: {"type":"response.output_item.done","item":{"type":"reasoning"}}',
      ]);
      expect((digest.starts, digest.stops), (1, 1));
      // Done carried none, so the one from added.
      expect(digest.signatures, ['enc_sig_multipart']);
      expect(digest.thinking, 'First part\n\nSecond part');
    });

    test('never emits the pre-content encrypted_content', () {
      final digest = digestThinking([
        'data: {"type":"response.output_item.added","item":{"type":"reasoning","encrypted_content":"enc_sig_pre_content_snapshot"}}',
        for (final part in ['A', 'B', 'C']) ...[
          'data: {"type":"response.reasoning_summary_part.added"}',
          'data: {"type":"response.reasoning_summary_text.delta","delta":"Part $part"}',
          'data: {"type":"response.reasoning_summary_part.done"}',
        ],
        'data: {"type":"response.output_item.done","item":{"type":"reasoning","encrypted_content":"enc_sig_final"}}',
      ]);
      expect((digest.starts, digest.stops), (1, 1));
      expect(digest.signatures, ['enc_sig_final']);
      expect(digest.raw, isNot(contains('enc_sig_pre_content_snapshot')));
      expect(digest.thinking, 'Part A\n\nPart B\n\nPart C');
    });

    test('one block per reasoning item', () {
      final digest = digestThinking([
        for (final n in [1, 2]) ...[
          'data: {"type":"response.output_item.added","item":{"type":"reasoning","encrypted_content":"enc_pre_$n"}}',
          'data: {"type":"response.reasoning_summary_part.added"}',
          'data: {"type":"response.reasoning_summary_text.delta","delta":"Item $n"}',
          'data: {"type":"response.reasoning_summary_part.done"}',
          'data: {"type":"response.output_item.done","item":{"type":"reasoning","encrypted_content":"enc_final_$n"}}',
        ],
      ]);
      expect((digest.starts, digest.stops), (2, 2));
      expect(digest.signatures, ['enc_final_1', 'enc_final_2']);
      expect(digest.raw, isNot(contains('enc_pre_1')));
      expect(digest.raw, isNot(contains('enc_pre_2')));
    });

    test('uses the early signature when done omits it', () {
      final digest = digestThinking([
        'data: {"type":"response.output_item.added","item":{"type":"reasoning","encrypted_content":"enc_sig_early"}}',
        'data: {"type":"response.reasoning_summary_part.added"}',
        'data: {"type":"response.reasoning_summary_text.delta","delta":"Let me think"}',
        'data: {"type":"response.output_item.done","item":{"type":"reasoning"}}',
      ]);
      expect(digest.signatures, ['enc_sig_early']);
    });

    test('uses the final done signature, in order', () {
      final events = <String>[];
      for (final d in dataOf(
        translate([
          'data: {"type":"response.output_item.added","item":{"type":"reasoning","encrypted_content":"enc_sig_initial"}}',
          'data: {"type":"response.reasoning_summary_part.added"}',
          'data: {"type":"response.reasoning_summary_text.delta","delta":"Let me think"}',
          'data: {"type":"response.reasoning_summary_part.done"}',
          'data: {"type":"response.output_item.done","item":{"type":"reasoning","encrypted_content":"enc_sig_final"}}',
        ]),
      )) {
        final type = d.get('type').string;
        if (type == 'content_block_start' &&
            d.get('content_block.type').string == 'thinking') {
          events.add('thinking_start');
        } else if (d.get('delta.type').string == 'thinking_delta') {
          events.add('thinking_delta');
        } else if (d.get('delta.type').string == 'signature_delta') {
          events.add('signature_delta');
          expect(d.get('delta.signature').string, 'enc_sig_final');
        } else if (type == 'content_block_stop' &&
            d.get('index').integer == 0) {
          events.add('thinking_stop');
        }
      }
      expect(
        events.join(','),
        'thinking_start,thinking_delta,signature_delta,thinking_stop',
      );
    });

    test('signature-only reasoning emits a signed thinking block', () {
      final events = <String>[];
      var textIndex = -1;
      for (final d in dataOf(
        translate([
          'data: {"type":"response.created","response":{"id":"resp_123","model":"gpt-5"}}',
          'data: {"type":"response.output_item.added","item":{"type":"reasoning","encrypted_content":"enc_sig_initial"}}',
          'data: {"type":"response.output_item.done","item":{"type":"reasoning","encrypted_content":"enc_sig_only"}}',
          'data: {"type":"response.content_part.added"}',
          'data: {"type":"response.output_text.delta","delta":"ok"}',
        ]),
      )) {
        switch (d.get('type').string) {
          case 'content_block_start':
            if (d.get('content_block.type').string == 'thinking') {
              events.add('thinking_start');
              expect(d.get('index').integer, 0);
            } else if (d.get('content_block.type').string == 'text') {
              events.add('text_start');
              textIndex = d.get('index').integer;
            }
          case 'content_block_delta':
            expect(d.get('delta.type').string, isNot('thinking_delta'));
            if (d.get('delta.type').string == 'signature_delta') {
              events.add('signature_delta');
              expect(d.get('index').integer, 0);
              expect(d.get('delta.signature').string, 'enc_sig_only');
            }
          case 'content_block_stop':
            if (d.get('index').integer == 0) events.add('thinking_stop');
        }
      }
      expect(textIndex, 1);
      expect(
        events.join(','),
        'thinking_start,signature_delta,thinking_stop,text_start',
      );
    });

    test('non-stream thinking includes the signature', () {
      final out = JsonValue(
        convertResponsesResponseToClaudeNonStream(
          '{"messages":[]}',
          '''{
          "type":"response.completed",
          "response":{"id":"resp_123","model":"gpt-5",
            "usage":{"input_tokens":10,"output_tokens":20},
            "output":[
              {"type":"reasoning","encrypted_content":"enc_sig_nonstream","summary":[{"type":"summary_text","text":"internal reasoning"}]},
              {"type":"message","content":[{"type":"output_text","text":"final answer"}]}]}}''',
        ),
      );
      final thinking = out.get('content.0');
      expect(thinking.get('type').string, 'thinking');
      expect(thinking.get('signature').string, 'enc_sig_nonstream');
      expect(thinking.get('thinking').string, 'internal reasoning');
    });
  });

  group('errors', () {
    test('cyber policy error', () {
      final out = translate([
        'data: {"type":"error","error":{"type":"invalid_request","code":"cyber_policy","message":"This content was flagged for possible cybersecurity risk.","param":null},"sequence_number":3}',
      ]).single;
      expect(out, contains('event: error\n'));
      final payload = firstPayloadForEvent(out, 'error')!;
      expect(payload.get('type').string, 'error');
      expect(payload.get('error.type').string, 'invalid_request_error');
      expect(
        payload.get('error.message').string,
        'This content was flagged for possible cybersecurity risk.',
      );
    });

    test('error_type is the fallback message', () {
      final out = translate([
        'data: {"type":"error","error":{},"error_type":"overloaded_error"}',
      ]).single;
      final payload = firstPayloadForEvent(out, 'error')!;
      expect(payload.get('error.type').string, 'overloaded_error');
      expect(payload.get('error.message').string, 'overloaded_error');
    });
  });

  group('function calls', () {
    test('text before tool calls emits no ghost stop', () {
      final starts = <int>[];
      final stops = <int>[];
      for (final d in dataOf(
        translate(request: '{"tools":[{"name":"Read","description":"read"}]}', [
          'data: {"type":"response.created","response":{"id":"resp_1","model":"grok-composer-2.5-fast"}}',
          'data: {"type":"response.output_item.added","item":{"type":"message","status":"in_progress"},"output_index":1}',
          'data: {"type":"response.content_part.added","part":{"type":"output_text"},"content_index":0,"output_index":1}',
          'data: {"type":"response.output_text.delta","delta":"查看项目的 README 和核心入口，以便准确说明项目用途。\\n","output_index":1}',
          'data: {"type":"response.output_item.added","item":{"type":"function_call","call_id":"call_a","name":"Read","status":"in_progress"},"output_index":2}',
          'data: {"type":"response.function_call_arguments.delta","delta":"{\\"path\\":\\"/tmp/README.md\\"}","output_index":2}',
          'data: {"type":"response.function_call_arguments.done","arguments":"{\\"path\\":\\"/tmp/README.md\\"}","output_index":2}',
          'data: {"type":"response.output_item.done","item":{"type":"function_call","call_id":"call_a","name":"Read","arguments":"{\\"path\\":\\"/tmp/README.md\\"}"},"output_index":2}',
          'data: {"type":"response.output_item.added","item":{"type":"function_call","call_id":"call_b","name":"Read","status":"in_progress"},"output_index":3}',
          'data: {"type":"response.function_call_arguments.delta","delta":"{\\"path\\":\\"/tmp/main.go\\"}","output_index":3}',
          'data: {"type":"response.content_part.done","part":{"type":"output_text"},"content_index":0,"output_index":1}',
          'data: {"type":"response.output_item.done","item":{"type":"message","status":"completed"},"output_index":1}',
          'data: {"type":"response.function_call_arguments.done","arguments":"{\\"path\\":\\"/tmp/main.go\\"}","output_index":3}',
          'data: {"type":"response.output_item.done","item":{"type":"function_call","call_id":"call_b","name":"Read","arguments":"{\\"path\\":\\"/tmp/main.go\\"}"},"output_index":3}',
          'data: {"type":"response.completed","response":{"usage":{"input_tokens":1,"output_tokens":1}}}',
        ]),
      )) {
        switch (d.get('type').string) {
          case 'content_block_start':
            starts.add(d.get('index').integer);
          case 'content_block_stop':
            stops.add(d.get('index').integer);
        }
      }
      expect(starts, [0, 1, 2]);
      expect(stops, [0, 1, 2]);
    });

    test('start waits for the name on done', () {
      final translator = ResponsesResponseTranslator(
        '{"tools":[{"name":"web_search","description":"search"}]}',
      );
      translator.convert(
        'data: {"type":"response.created","response":{"id":"resp_1","model":"gpt-5"}}',
      );
      final added = translator.convert(
        'data: {"type":"response.output_item.added","item":{"type":"function_call","call_id":"call_1"},"output_index":1}',
      );
      final arguments = translator.convert(
        'data: {"type":"response.function_call_arguments.done","arguments":"{\\"query\\":\\"example\\"}","output_index":1}',
      );
      final done = translator.convert(
        'data: {"type":"response.output_item.done","item":{"type":"function_call","call_id":"call_1","name":"web_search","arguments":"{\\"query\\":\\"example\\"}"},"output_index":1}',
      );
      expect(added, isNot(contains('"content_block_start"')));
      expect(arguments, isNot(contains('"input_json_delta"')));
      final data = dataOf([done]);
      final starts = data.where(
        (d) => d.get('content_block.type').string == 'tool_use',
      );
      expect(starts, hasLength(1));
      expect(starts.single.get('content_block.name').string, 'web_search');
      expect(
        [
          for (final d in data)
            if (d.get('delta.type').string == 'input_json_delta')
              d.get('delta.partial_json').string,
        ],
        ['{"query":"example"}'],
      );
      expect(
        data.where((d) => d.get('type').string == 'content_block_stop'),
        hasLength(1),
      );
    });

    test('unnamed calls done by call_id keep their slots', () {
      final ids = <String>[];
      final starts = <int>[];
      final stops = <int>[];
      final deltas = <String>[];
      for (final d in dataOf(
        translate(request: lookupRequest, [
          'data: {"type":"response.created","response":{"id":"resp_1","model":"gpt-5"}}',
          'data: {"type":"response.output_item.added","item":{"type":"function_call","call_id":"call_first"},"output_index":1}',
          'data: {"type":"response.output_item.added","item":{"type":"function_call","call_id":"call_second"},"output_index":2}',
          'data: {"type":"response.output_item.done","item":{"type":"function_call","call_id":"call_first","name":"lookup","arguments":"{\\"id\\":1}"}}',
          'data: {"type":"response.output_item.done","item":{"type":"function_call","call_id":"call_second","name":"lookup","arguments":"{\\"id\\":2}"}}',
        ]),
      )) {
        switch (d.get('type').string) {
          case 'content_block_start'
              when d.get('content_block.type').string == 'tool_use':
            ids.add(d.get('content_block.id').string);
            starts.add(d.get('index').integer);
          case 'content_block_delta'
              when d.get('delta.type').string == 'input_json_delta':
            deltas.add(d.get('delta.partial_json').string);
          case 'content_block_stop':
            stops.add(d.get('index').integer);
        }
      }
      expect(ids, ['call_first', 'call_second']);
      expect(starts, [0, 1]);
      expect(stops, [0, 1]);
      expect(deltas, ['{"id":1}', '{"id":2}']);
    });

    test('a deferred unnamed call reserves no block index', () {
      final text =
          dataOf(
            translate(request: lookupRequest, [
              'data: {"type":"response.created","response":{"id":"resp_1","model":"gpt-5"}}',
              'data: {"type":"response.output_item.added","item":{"type":"function_call","call_id":"call_hidden"},"output_index":1}',
              'data: {"type":"response.output_item.done","item":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"ok"}]},"output_index":2}',
            ]),
          ).firstWhere(
            (d) =>
                d.get('type').string == 'content_block_start' &&
                d.get('content_block.type').string == 'text',
          );
      expect(text.get('index').integer, 0);
    });

    test('terminal output fills an open call\'s arguments', () {
      var position = 0;
      var arguments = -1;
      var stop = -1;
      var delta = -1;
      for (final d in dataOf(
        translate(request: lookupRequest, [
          'data: {"type":"response.created","response":{"id":"resp_1","model":"gpt-5"}}',
          'data: {"type":"response.output_item.added","item":{"type":"function_call","call_id":"call_1","name":"lookup"},"output_index":1}',
          'data: {"type":"response.completed","response":{"stop_reason":"stop","usage":{"input_tokens":1,"output_tokens":1},"output":[{"type":"function_call","call_id":"call_1","name":"lookup","arguments":"{\\"query\\":\\"example\\"}"}]}}',
        ]),
      )) {
        position++;
        switch (d.get('type').string) {
          case 'content_block_delta'
              when d.get('delta.type').string == 'input_json_delta' &&
                  d.get('delta.partial_json').string == '{"query":"example"}':
            arguments = position;
          case 'content_block_stop' when d.get('index').integer == 0:
            stop = position;
          case 'message_delta':
            delta = position;
        }
      }
      expect(arguments, isNot(-1));
      expect(stop, isNot(-1));
      expect(delta, isNot(-1));
      expect(arguments < stop && stop < delta, isTrue);
    });

    test('terminal output emits a pending unnamed call', () {
      final outputs = translate(request: lookupRequest, [
        'data: {"type":"response.created","response":{"id":"resp_1","model":"gpt-5"}}',
        'data: {"type":"response.output_item.added","item":{"type":"function_call","call_id":"call_1"},"output_index":1}',
        'data: {"type":"response.function_call_arguments.done","arguments":"{\\"query\\":\\"example\\"}","output_index":1}',
        'data: {"type":"response.completed","response":{"stop_reason":"stop","usage":{"input_tokens":1,"output_tokens":1},"output":[{"type":"function_call","call_id":"call_1","name":"lookup","arguments":"{\\"query\\":\\"example\\"}"}]}}',
      ]);
      final text = outputs.join();
      expect('"type":"tool_use"'.allMatches(text), hasLength(1));
      expect(text, contains('"name":"lookup"'));
      expect(text, contains(r'"partial_json":"{\"query\":\"example\"}"'));
      expect(stopReason(outputs), 'tool_use');
      expect(
        text.indexOf('"type":"tool_use"'),
        lessThan(text.indexOf('"type":"message_delta"')),
      );
    });

    test('an unresolved pending call does not force tool_use', () {
      final translator = ResponsesResponseTranslator(lookupRequest);
      final outputs = feed(translator, [
        'data: {"type":"response.created","response":{"id":"resp_1","model":"gpt-5"}}',
        'data: {"type":"response.output_item.added","item":{"type":"function_call","call_id":"call_hidden"},"output_index":1}',
        'data: {"type":"response.completed","response":{"stop_reason":"stop","usage":{"input_tokens":1,"output_tokens":1},"output":[]}}',
      ]);
      expect(outputs.join(), isNot(contains('"type":"tool_use"')));
      expect(stopReason(outputs), 'end_turn');
      expect(translator.hasPendingFunctionCalls, isFalse);
    });

    test('shortens long tool_use ids', () {
      final longCallId = 'call_${'a' * 62}';
      final start = dataOf(
        translate(request: lookupSchemaRequest, [
          'data: {"type":"response.output_item.added","item":{"type":"function_call","call_id":"$longCallId","name":"lookup"}}',
        ]),
      ).firstWhere((d) => d.get('content_block.type').string == 'tool_use');
      final streamId = start.get('content_block.id').string;
      expect(streamId.length, lessThanOrEqualTo(64));
      expect(streamId, isNot(longCallId));

      final out = JsonValue(
        convertResponsesResponseToClaudeNonStream(
          lookupSchemaRequest,
          '''{
          "type":"response.completed",
          "response":{"id":"resp_1","model":"gpt-5","usage":{"input_tokens":1,"output_tokens":1},
            "output":[{"type":"function_call","call_id":"$longCallId","name":"lookup","arguments":"{}"}]}}''',
        ),
      );
      final id = out.get('content.0.id').string;
      expect(id, isNotEmpty);
      expect(id.length, lessThanOrEqualTo(64));
      expect(id, isNot(longCallId));
    });
  });

  test('empty terminal output falls back to output_item.done message', () {
    final data = dataOf(
      translate(request: '{"tools":[]}', [
        'data: {"type":"response.created","response":{"id":"resp_1","model":"gpt-5"}}',
        'data: {"type":"response.output_item.done","item":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"ok"}]},"output_index":0}',
        'data: {"type":"response.completed","response":{"usage":{"input_tokens":1,"output_tokens":1}}}',
      ]),
    );
    expect(
      data.any(
        (d) =>
            d.get('delta.type').string == 'text_delta' &&
            d.get('delta.text').string == 'ok',
      ),
      isTrue,
    );
  });

  group('web search', () {
    test('stream emits Claude server tool blocks', () {
      final text = translate(request: webSearchRequest, [
        'data: {"type":"response.created","response":{"id":"resp_1","model":"gpt-5.4"}}',
        'data: {"type":"response.output_item.added","item":{"id":"ws_123","type":"web_search_call","status":"in_progress"}}',
        'data: {"type":"response.web_search_call.searching","item_id":"ws_123"}',
        'data: {"type":"response.web_search_call.completed","item_id":"ws_123"}',
        'data: {"type":"response.output_item.done","item":{"id":"ws_123","type":"web_search_call","status":"completed","action":{"type":"search","query":"search weather"}}}',
        'data: {"type":"response.completed","response":{"stop_reason":"stop","usage":{"input_tokens":3,"output_tokens":2}}}',
      ]).join();
      for (final needle in [
        '"type":"server_tool_use"',
        '"id":"ws_123"',
        '"type":"web_search_tool_result"',
        'event: message_stop',
      ]) {
        expect(text, contains(needle));
      }
      expect(
        text.indexOf('"type":"web_search_tool_result"'),
        greaterThan(text.indexOf('"type":"server_tool_use"')),
      );
      expect(text, contains('partial_json'));
      expect(text, contains('search weather'));
    });

    test('stream reuses the fallback tool_use id', () {
      final text = translate(request: webSearchRequest, [
        'data: {"type":"response.created","response":{"id":"resp_1","model":"gpt-5.4"}}',
        'data: {"type":"response.output_item.added","item":{"type":"web_search_call","status":"in_progress"}}',
        'data: {"type":"response.web_search_call.completed","item_id":"ws_from_upstream"}',
        'data: {"type":"response.output_item.done","item":{"id":"ws_from_upstream","type":"web_search_call","status":"completed","action":{"type":"search","query":"search weather"}}}',
        'data: {"type":"response.completed","response":{"stop_reason":"stop","usage":{"input_tokens":3,"output_tokens":2}}}',
      ]).join();
      expect('"type":"server_tool_use"'.allMatches(text), hasLength(1));
      expect(text, contains('"tool_use_id":"ws_from_upstream"'));
    });

    const nonStream =
        '{"type":"response.completed","response":{"id":"resp_1","model":"gpt-5.3-codex-spark","stop_reason":"stop","usage":{"input_tokens":3,"output_tokens":2},"output":[{"type":"web_search_call","id":"ws_123","status":"completed","action":{"type":"search","query":"search weather"}},{"type":"message","content":[{"type":"output_text","text":"done"}]}]}}';

    test('non-stream emits server tool blocks', () {
      final out = JsonValue(
        convertResponsesResponseToClaudeNonStream(webSearchRequest, nonStream),
      );
      final types = [
        for (final c in out.get('content').array) c.get('type').string,
      ];
      expect(
        types,
        containsAll(['server_tool_use', 'web_search_tool_result', 'text']),
      );
      expect(out.raw, contains('search weather'));
    });

    test('non-stream stop reason is end_turn', () {
      final out = JsonValue(
        convertResponsesResponseToClaudeNonStream(webSearchRequest, nonStream),
      );
      expect(out.get('stop_reason').string, 'end_turn');
    });

    test('non-stream dedupes empty open_page items', () {
      final out = JsonValue(
        convertResponsesResponseToClaudeNonStream(
          '{"tools":[{"type":"web_search_20250305","name":"web_search"}],"messages":[{"role":"user","content":"q"}]}',
          '{"type":"response.completed","response":{"id":"resp_1","model":"gpt-5.3-codex-spark","stop_reason":"stop","usage":{"input_tokens":1,"output_tokens":1},"output":[{"type":"web_search_call","id":"ws_1","status":"completed","action":{"type":"open_page"}},{"type":"web_search_call","id":"ws_1","status":"completed","action":{"type":"search","query":"weather"}},{"type":"message","content":[{"type":"output_text","text":"ok"}]}]}}',
        ),
      );
      expect('"type":"server_tool_use"'.allMatches(out.raw), hasLength(1));
      expect(out.raw, contains('weather'));
    });
  });

  group('stop reasons', () {
    const usage = '"usage":{"input_tokens":1,"output_tokens":1}';
    final streamCases = [
      (
        name: 'stop maps to end_turn',
        chunks: [
          'data: {"type":"response.completed","response":{"stop_reason":"stop",$usage}}',
        ],
        want: 'end_turn',
      ),
      (
        name: 'incomplete max output maps to max_tokens',
        chunks: [
          'data: {"type":"response.incomplete","response":{"incomplete_details":{"reason":"max_output_tokens"},$usage}}',
        ],
        want: 'max_tokens',
      ),
      (
        name: 'tool call wins over stop',
        chunks: [
          'data: {"type":"response.output_item.added","item":{"type":"function_call","call_id":"call_1","name":"lookup"}}',
          'data: {"type":"response.completed","response":{"stop_reason":"stop",$usage}}',
        ],
        want: 'tool_use',
      ),
      (
        name: 'content filter maps to refusal',
        chunks: [
          'data: {"type":"response.incomplete","response":{"incomplete_details":{"reason":"content_filter"},$usage}}',
        ],
        want: 'refusal',
      ),
    ];
    for (final c in streamCases) {
      test('stream: ${c.name}', () {
        expect(
          stopReason(translate(c.chunks, request: lookupSchemaRequest)),
          c.want,
        );
      });
    }

    test('stream stop sequence', () {
      final delta = messageDelta(
        translate([
          'data: {"type":"response.completed","response":{"stop_reason":"stop","stop_sequence":"\\nEND",$usage}}',
        ]),
      )!;
      expect(delta.get('delta.stop_reason').string, 'stop_sequence');
      expect(delta.get('delta.stop_sequence').string, '\nEND');
    });

    final nonStreamCases = [
      (
        name: 'stop maps to end_turn',
        response:
            '{"type":"response.completed","response":{"id":"resp_1","model":"gpt-5","stop_reason":"stop",$usage,"output":[]}}',
        want: 'end_turn',
      ),
      (
        name: 'incomplete max output maps to max_tokens',
        response:
            '{"type":"response.incomplete","response":{"id":"resp_1","model":"gpt-5","incomplete_details":{"reason":"max_output_tokens"},$usage,"output":[]}}',
        want: 'max_tokens',
      ),
      (
        name: 'tool call wins over stop',
        response:
            '{"type":"response.completed","response":{"id":"resp_1","model":"gpt-5","stop_reason":"stop",$usage,"output":[{"type":"function_call","call_id":"call_1","name":"lookup","arguments":"{}"}]}}',
        want: 'tool_use',
      ),
      (
        name: 'content filter maps to refusal',
        response:
            '{"type":"response.incomplete","response":{"id":"resp_1","model":"gpt-5","incomplete_details":{"reason":"content_filter"},$usage,"output":[]}}',
        want: 'refusal',
      ),
    ];
    for (final c in nonStreamCases) {
      test('non-stream: ${c.name}', () {
        final out = JsonValue(
          convertResponsesResponseToClaudeNonStream(
            lookupSchemaRequest,
            c.response,
          ),
        );
        expect(out.get('stop_reason').string, c.want);
      });
    }

    test('non-stream stop sequence', () {
      final out = JsonValue(
        convertResponsesResponseToClaudeNonStream(
          '{"messages":[]}',
          '{"type":"response.completed","response":{"id":"resp_1","model":"gpt-5","stop_reason":"stop","stop_sequence":"\\nEND",$usage,"output":[]}}',
        ),
      );
      expect(out.get('stop_reason').string, 'stop_sequence');
      expect(out.get('stop_sequence').string, '\nEND');
    });
  });

  const cacheCases = [
    (
      name: 'cache_write_tokens field',
      usage: '{"input_tokens":1000,"output_tokens":200,"input_tokens_details":{"cached_tokens":800,"cache_write_tokens":150}}',
      want: (50, 200, 800, 150),
    ),
    (
      name: 'cache_creation_tokens alias',
      usage: '{"input_tokens":1000,"output_tokens":200,"input_tokens_details":{"cached_tokens":800,"cache_creation_tokens":150}}',
      want: (50, 200, 800, 150),
    ),
    (
      name: 'cached_tokens greater than input clamps to zero',
      usage: '{"input_tokens":500,"output_tokens":100,"input_tokens_details":{"cached_tokens":800,"cache_write_tokens":50}}',
      want: (0, 100, 800, 50),
    ),
    (
      name: 'zero cache_write_tokens emits no cache_creation_input_tokens',
      usage: '{"input_tokens":1000,"output_tokens":200,"input_tokens_details":{"cached_tokens":800,"cache_write_tokens":0}}',
      want: (200, 200, 800, 0),
    ),
    (
      name: 'cache_write_tokens only deducts from input',
      usage: '{"input_tokens":4022,"output_tokens":462,"input_tokens_details":{"cached_tokens":0,"cache_write_tokens":4019}}',
      want: (3, 462, 0, 4019),
    ),
    (
      name: 'cached and cache_write greater than input clamp to zero',
      usage: '{"input_tokens":500,"output_tokens":100,"input_tokens_details":{"cached_tokens":300,"cache_write_tokens":300}}',
      want: (0, 100, 300, 300),
    ),
  ];

  void expectCacheUsage(JsonValue usage, (int, int, int, int) want) {
    final (input, output, cacheRead, cacheWrite) = want;
    expect(usage.get('input_tokens').integer, input);
    expect(usage.get('output_tokens').integer, output);
    expect(usage.get('cache_read_input_tokens').integer, cacheRead);
    if (cacheWrite == 0) {
      expect(usage.get('cache_creation_input_tokens').exists, isFalse);
    } else {
      expect(usage.get('cache_creation_input_tokens').integer, cacheWrite);
    }
  }

  List<String> streamWithUsage(String usage) => translate([
    'data: {"type":"response.created","response":{"id":"resp_1","model":"gpt-5"}}',
    'data: {"type":"response.output_item.done","item":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"ok"}]}}',
    'data: {"type":"response.completed","response":{"stop_reason":"stop","usage":$usage}}',
  ]);

  JsonValue nonStreamWithUsage(String usage) => JsonValue(
    convertResponsesResponseToClaudeNonStream(
      '{"messages":[]}',
      '{"type":"response.completed","response":{"id":"resp_1","model":"gpt-5","stop_reason":"stop","usage":$usage,"output":[{"type":"message","content":[{"type":"output_text","text":"ok"}]}]}}',
    ),
  );

  group('cache write usage', () {
    for (final c in cacheCases) {
      test('stream: ${c.name}', () {
        expectCacheUsage(
          messageDelta(streamWithUsage(c.usage))!.get('usage'),
          c.want,
        );
      });
      test('non-stream: ${c.name}', () {
        expectCacheUsage(nonStreamWithUsage(c.usage).get('usage'), c.want);
      });
    }
  });

  group('reasoning usage', () {
    const cases = [
      (
        name: 'keeps positive reasoning tokens',
        usage: '{"input_tokens":420,"output_tokens":518,"output_tokens_details":{"reasoning_tokens":163},"total_tokens":938}',
        output: 518,
        reasoning: 163,
      ),
      (
        name: 'keeps explicit zero reasoning tokens',
        usage: '{"input_tokens":100,"output_tokens":50,"output_tokens_details":{"reasoning_tokens":0}}',
        output: 50,
        reasoning: 0,
      ),
      (
        name: 'omits absent reasoning detail',
        usage: '{"input_tokens":100,"output_tokens":50}',
        output: 50,
        reasoning: null,
      ),
      (
        name: 'clamps oversized reasoning tokens to output',
        usage: '{"input_tokens":100,"output_tokens":50,"output_tokens_details":{"reasoning_tokens":999}}',
        output: 50,
        reasoning: 50,
      ),
      (
        name: 'rejects negative reasoning tokens',
        usage: '{"input_tokens":100,"output_tokens":50,"output_tokens_details":{"reasoning_tokens":-5}}',
        output: 50,
        reasoning: null,
      ),
      (
        name: 'rejects negative float reasoning tokens',
        usage: '{"input_tokens":100,"output_tokens":50,"output_tokens_details":{"reasoning_tokens":-0.5}}',
        output: 50,
        reasoning: null,
      ),
      (
        name: 'clamps int64-overflowing reasoning tokens to output',
        usage: '{"input_tokens":100,"output_tokens":50,"output_tokens_details":{"reasoning_tokens":9223372036854775808}}',
        output: 50,
        reasoning: 50,
      ),
      (
        name: 'omits string reasoning detail',
        usage: '{"input_tokens":100,"output_tokens":50,"output_tokens_details":{"reasoning_tokens":"163"}}',
        output: 50,
        reasoning: null,
      ),
      (
        name: 'omits boolean reasoning detail',
        usage: '{"input_tokens":100,"output_tokens":50,"output_tokens_details":{"reasoning_tokens":true}}',
        output: 50,
        reasoning: null,
      ),
      (
        name: 'omits null reasoning detail',
        usage: '{"input_tokens":100,"output_tokens":50,"output_tokens_details":{"reasoning_tokens":null}}',
        output: 50,
        reasoning: null,
      ),
    ];

    void expectReasoning(JsonValue usage, int output, int? reasoning) {
      expect(usage.get('output_tokens').integer, output);
      final thinking = usage.get('output_tokens_details.thinking_tokens');
      expect(thinking.exists, reasoning != null);
      if (reasoning != null) expect(thinking.integer, reasoning);
    }

    for (final c in cases) {
      test('stream: ${c.name}', () {
        expectReasoning(
          messageDelta(streamWithUsage(c.usage))!.get('usage'),
          c.output,
          c.reasoning,
        );
      });
      test('non-stream: ${c.name}', () {
        expectReasoning(
          nonStreamWithUsage(c.usage).get('usage'),
          c.output,
          c.reasoning,
        );
      });
    }
  });

  group('extractResponsesUsage', () {
    const cases = [
      (name: 'absent usage', raw: '', want: (0, 0, 0, 0)),
      (name: 'null usage', raw: 'null', want: (0, 0, 0, 0)),
      (
        name: 'no cache details',
        raw: '{"input_tokens":100,"output_tokens":50}',
        want: (100, 50, 0, 0),
      ),
      (
        name: 'deducts cached_tokens only',
        raw: '{"input_tokens":100,"output_tokens":50,"input_tokens_details":{"cached_tokens":30}}',
        want: (70, 50, 30, 0),
      ),
      (
        name: 'deducts cache_write_tokens only',
        raw: '{"input_tokens":4022,"output_tokens":462,"input_tokens_details":{"cache_write_tokens":4019}}',
        want: (3, 462, 0, 4019),
      ),
      (
        name: 'deducts cache_creation_tokens alias only',
        raw: '{"input_tokens":4022,"output_tokens":462,"input_tokens_details":{"cache_creation_tokens":4019}}',
        want: (3, 462, 0, 4019),
      ),
      (
        name: 'deducts both',
        raw: '{"input_tokens":1000,"output_tokens":200,"input_tokens_details":{"cached_tokens":800,"cache_write_tokens":150}}',
        want: (50, 200, 800, 150),
      ),
      (
        name: 'clamps input to zero when cache exceeds it',
        raw: '{"input_tokens":500,"output_tokens":100,"input_tokens_details":{"cached_tokens":300,"cache_write_tokens":300}}',
        want: (0, 100, 300, 300),
      ),
      (
        name: 'negative cache numbers leave input alone',
        raw: '{"input_tokens":100,"output_tokens":50,"input_tokens_details":{"cached_tokens":-10,"cache_write_tokens":-5}}',
        want: (100, 50, -10, 0),
      ),
      (
        name: 'clamps negative input_tokens to zero',
        raw: '{"input_tokens":-10,"output_tokens":50}',
        want: (0, 50, 0, 0),
      ),
      (
        name: 'negative cache_write_tokens falls back to cache_creation_tokens',
        raw: '{"input_tokens":100,"output_tokens":50,"input_tokens_details":{"cache_write_tokens":-1,"cache_creation_tokens":40}}',
        want: (60, 50, 0, 40),
      ),
      (
        name: 'huge counts do not overflow',
        raw: '{"input_tokens":100,"output_tokens":50,"input_tokens_details":{"cached_tokens":9223372036854775800,"cache_write_tokens":100}}',
        want: (0, 50, 9223372036854775800, 100),
      ),
    ];
    for (final c in cases) {
      test(c.name, () {
        final usage = c.raw.isEmpty
            ? JsonValue.missing
            : JsonValue.parse(c.raw);
        expect(extractResponsesUsage(usage), c.want);
      });
    }
  });

  group('parallel function calls', () {
    test('interleaved named calls, first finishes first', () {
      expectParallelReadCalls(
        parallelLifecycle([
          'data: {"type":"response.created","response":{"id":"resp_parallel","model":"gpt-5"}}',
          'data: {"type":"response.output_item.added","item":{"type":"function_call","call_id":"call_a","name":"Read"},"output_index":1}',
          'data: {"type":"response.output_item.added","item":{"type":"function_call","call_id":"call_b","name":"Read"},"output_index":2}',
          'data: {"type":"response.function_call_arguments.delta","delta":"{\\"file_path\\":\\"a\\"}","output_index":1}',
          'data: {"type":"response.function_call_arguments.delta","delta":"{\\"file_path\\":\\"b\\"}","output_index":2}',
          'data: {"type":"response.function_call_arguments.done","arguments":"{\\"file_path\\":\\"a\\"}","output_index":1}',
          'data: {"type":"response.output_item.done","item":{"type":"function_call","call_id":"call_a","name":"Read","arguments":"{\\"file_path\\":\\"a\\"}"},"output_index":1}',
          'data: {"type":"response.function_call_arguments.done","arguments":"{\\"file_path\\":\\"b\\"}","output_index":2}',
          'data: {"type":"response.output_item.done","item":{"type":"function_call","call_id":"call_b","name":"Read","arguments":"{\\"file_path\\":\\"b\\"}"},"output_index":2}',
        ]),
      );
    });

    test('interleaved named calls, second finishes first', () {
      expectParallelReadCalls(
        parallelLifecycle([
          'data: {"type":"response.created","response":{"id":"resp_parallel","model":"gpt-5"}}',
          'data: {"type":"response.output_item.added","item":{"type":"function_call","call_id":"call_a","name":"Read"},"output_index":1}',
          'data: {"type":"response.output_item.added","item":{"type":"function_call","call_id":"call_b","name":"Read"},"output_index":2}',
          'data: {"type":"response.function_call_arguments.delta","delta":"{\\"file_path\\":\\"b\\"}","output_index":2}',
          'data: {"type":"response.function_call_arguments.done","arguments":"{\\"file_path\\":\\"b\\"}","output_index":2}',
          'data: {"type":"response.output_item.done","item":{"type":"function_call","call_id":"call_b","name":"Read","arguments":"{\\"file_path\\":\\"b\\"}"},"output_index":2}',
          'data: {"type":"response.function_call_arguments.delta","delta":"{\\"file_path\\":\\"a\\"}","output_index":1}',
          'data: {"type":"response.function_call_arguments.done","arguments":"{\\"file_path\\":\\"a\\"}","output_index":1}',
          'data: {"type":"response.output_item.done","item":{"type":"function_call","call_id":"call_a","name":"Read","arguments":"{\\"file_path\\":\\"a\\"}"},"output_index":1}',
        ]),
      );
    });

    for (final (name, call, first, second) in [
      (
        'named active call',
        'data: {"type":"response.output_item.added","item":{"type":"function_call","call_id":"call_a","name":"Read"},"output_index":0}',
        'tool_use',
        'text',
      ),
      (
        'unnamed pending call',
        'data: {"type":"response.output_item.added","item":{"type":"function_call","call_id":"call_a"},"output_index":0}',
        'text',
        'tool_use',
      ),
    ]) {
      test('other content waits for calls to close: $name', () {
        final blocks = parallelLifecycle([
          'data: {"type":"response.created","response":{"id":"resp_mixed","model":"gpt-5"}}',
          call,
          'data: {"type":"response.output_item.added","item":{"type":"message","status":"in_progress"},"output_index":1}',
          'data: {"type":"response.content_part.added","part":{"type":"output_text"},"content_index":0,"output_index":1}',
          'data: {"type":"response.output_text.delta","delta":"done","output_index":1}',
          'data: {"type":"response.content_part.done","part":{"type":"output_text"},"content_index":0,"output_index":1}',
          'data: {"type":"response.output_item.done","item":{"type":"message","status":"completed"},"output_index":1}',
          'data: {"type":"response.function_call_arguments.done","arguments":"{\\"file_path\\":\\"a\\"}","output_index":0}',
          'data: {"type":"response.output_item.done","item":{"type":"function_call","call_id":"call_a","name":"Read","arguments":"{\\"file_path\\":\\"a\\"}"},"output_index":0}',
          'data: {"type":"response.completed","response":{"usage":{"input_tokens":1,"output_tokens":1}}}',
        ]);
        expect(blocks, hasLength(2));
        expect((blocks[0].index, blocks[0].type), (0, first));
        expect((blocks[1].index, blocks[1].type), (1, second));
        for (final block in blocks) {
          if (block.type == 'tool_use') {
            expect(block.arguments, '{"file_path":"a"}');
          }
          if (block.type == 'text') expect(block.text, 'done');
        }
      });
    }

    test('deferred text closes before thinking starts', () {
      final blocks = parallelLifecycle([
        'data: {"type":"response.created","response":{"id":"resp_mixed","model":"gpt-5"}}',
        'data: {"type":"response.output_item.added","item":{"type":"function_call","call_id":"call_a","name":"Read"},"output_index":0}',
        'data: {"type":"response.content_part.added","part":{"type":"output_text"},"content_index":0,"output_index":1}',
        'data: {"type":"response.output_text.delta","delta":"answer","output_index":1}',
        'data: {"type":"response.output_item.added","item":{"type":"reasoning","encrypted_content":"enc_initial"},"output_index":2}',
        'data: {"type":"response.reasoning_summary_part.added","output_index":2}',
        'data: {"type":"response.reasoning_summary_text.delta","delta":"thought","output_index":2}',
        'data: {"type":"response.output_item.done","item":{"type":"reasoning","encrypted_content":"enc_final"},"output_index":2}',
        'data: {"type":"response.function_call_arguments.done","arguments":"{\\"file_path\\":\\"a\\"}","output_index":0}',
        'data: {"type":"response.output_item.done","item":{"type":"function_call","call_id":"call_a","name":"Read","arguments":"{\\"file_path\\":\\"a\\"}"},"output_index":0}',
        'data: {"type":"response.completed","response":{"usage":{"input_tokens":1,"output_tokens":1}}}',
      ]);
      expect(blocks, hasLength(3));
      expect(
        (blocks[0].index, blocks[0].type, blocks[0].arguments),
        (0, 'tool_use', '{"file_path":"a"}'),
      );
      expect(
        (blocks[1].index, blocks[1].type, blocks[1].text),
        (1, 'text', 'answer'),
      );
      expect((blocks[2].index, blocks[2].type), (2, 'thinking'));
    });

    test('terminal matches calls by output index', () {
      final blocks = parallelLifecycle([
        'data: {"type":"response.created","response":{"id":"resp_parallel","model":"gpt-5"}}',
        'data: {"type":"response.output_item.added","item":{"type":"function_call","name":"Read"},"output_index":0}',
        'data: {"type":"response.output_item.added","item":{"type":"function_call","name":"Read"},"output_index":1}',
        'data: {"type":"response.completed","response":{"usage":{"input_tokens":1,"output_tokens":1},"output":[{"type":"function_call","name":"Read","arguments":"{\\"file_path\\":\\"a\\"}"},{"type":"function_call","name":"Read","arguments":"{\\"file_path\\":\\"b\\"}"}]}}',
      ]);
      expect(blocks, hasLength(2));
      expect((blocks[0].index, blocks[0].arguments), (0, '{"file_path":"a"}'));
      expect((blocks[1].index, blocks[1].arguments), (1, '{"file_path":"b"}'));
    });

    for (final terminal in ['response.completed', 'response.incomplete']) {
      test('terminal fills interleaved calls: $terminal', () {
        expectParallelReadCalls(
          parallelLifecycle([
            'data: {"type":"response.created","response":{"id":"resp_parallel","model":"gpt-5"}}',
            'data: {"type":"response.output_item.added","item":{"type":"function_call","call_id":"call_a","name":"Read"},"output_index":0}',
            'data: {"type":"response.output_item.added","item":{"type":"function_call","call_id":"call_b","name":"Read"},"output_index":1}',
            'data: {"type":"response.function_call_arguments.delta","delta":"{\\"file_path\\":","output_index":0}',
            'data: {"type":"$terminal","response":{"usage":{"input_tokens":1,"output_tokens":1},"output":[{"type":"function_call","call_id":"call_a","name":"Read","arguments":"{\\"file_path\\":\\"a\\"}"},{"type":"function_call","call_id":"call_b","name":"Read","arguments":"{\\"file_path\\":\\"b\\"}"}]}}',
          ]),
        );
      });
    }
  });

  // Not in the Go tests: a streamed tool call and its text, end to end,
  // with the message envelope.
  test('stream round trip', () {
    final outputs = translate(
      request: '{"stream":true,"tools":[{"name":"Read"}]}',
      [
        'data: {"type":"response.created","response":{"id":"resp_rt","model":"gpt-5"}}',
        'data: {"type":"response.output_item.added","item":{"type":"message"},"output_index":0}',
        'data: {"type":"response.content_part.added","part":{"type":"output_text"},"output_index":0}',
        'data: {"type":"response.output_text.delta","delta":"Reading.","output_index":0}',
        'data: {"type":"response.output_item.done","item":{"type":"message","status":"completed"},"output_index":0}',
        'data: {"type":"response.output_item.added","item":{"type":"function_call","call_id":"call_rt","name":"Read"},"output_index":1}',
        'data: {"type":"response.function_call_arguments.delta","delta":"{\\"file_path\\":","output_index":1}',
        'data: {"type":"response.function_call_arguments.delta","delta":"\\"x\\"}","output_index":1}',
        'data: {"type":"response.output_item.done","item":{"type":"function_call","call_id":"call_rt","name":"Read","arguments":"{\\"file_path\\":\\"x\\"}"},"output_index":1}',
        'data: {"type":"response.completed","response":{"usage":{"input_tokens":5,"output_tokens":7}}}',
      ],
    );
    final data = dataOf(outputs);
    expect(data.first.get('type').string, 'message_start');
    expect(data.first.get('message.id').string, 'resp_rt');
    expect(data.last.get('type').string, 'message_stop');
    final blocks = blockLifecycle(outputs);
    expect([for (final b in blocks) b.type], ['text', 'tool_use']);
    expect(blocks[0].text, 'Reading.');
    expect(blocks[1].id, 'call_rt');
    expect(blocks[1].arguments, '{"file_path":"x"}');
    expect(stopReason(outputs), 'tool_use');
    expect(messageDelta(outputs)!.get('usage.output_tokens').integer, 7);
  });
}
