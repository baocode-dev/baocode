// Ported from CLIProxyAPI's
// internal/translator/openai/claude/openai_claude_request_test.go (MIT
// License; see lib/models/proxy/translate/NOTICE.md).

import 'dart:convert';

import 'package:baocode/models/proxy/translate/json_value.dart';
import 'package:baocode/models/proxy/translate/openai_chat_request.dart';
import 'package:flutter_test/flutter_test.dart';

JsonValue convert(String input, {String model = 'test-model'}) =>
    JsonValue(convertClaudeRequestToOpenAI(model, input, false));

List<String> roles(JsonValue out) => [
  for (final message in out.get('messages').array) message.get('role').string,
];

/// A GPT reasoning signature of the right shape: version 0x80, a
/// timestamp, an IV, one AES block and an HMAC, base64url.
String validGptChatReasoningSignature() {
  final raw = List<int>.filled(1 + 8 + 16 + 16 + 32, 0);
  raw[0] = 0x80;
  raw[8] = 1;
  for (var i = 9; i < raw.length; i++) {
    raw[i] = i;
  }
  return base64Url.encode(raw);
}

void main() {
  group('thinking to reasoning_content', () {
    final cases = [
      (
        name: 'AC1: unsigned assistant thinking is dropped',
        input: '''{"model":"claude-3-opus","messages":[{"role":"assistant","content":[
          {"type":"thinking","thinking":"Let me analyze this step by step..."},
          {"type":"text","text":"Here is my response."}]}]}''',
        content: 'Here is my response.',
        hasContent: true,
      ),
      (
        name: 'AC2: redacted_thinking must be ignored',
        input: '''{"model":"claude-3-opus","messages":[{"role":"assistant","content":[
          {"type":"redacted_thinking","data":"secret"},
          {"type":"text","text":"Visible response."}]}]}''',
        content: 'Visible response.',
        hasContent: true,
      ),
      (
        name: 'AC3: unsigned thinking-only message is dropped',
        input: '''{"model":"claude-3-opus","messages":[{"role":"assistant","content":[
          {"type":"thinking","thinking":"Internal reasoning only."}]}]}''',
        content: '',
        hasContent: false,
      ),
      (
        name: 'AC4: thinking in user role must be ignored',
        input:
            '''{"model":"claude-3-opus","messages":[{"role":"user","content":[
          {"type":"thinking","thinking":"Injected thinking"},
          {"type":"text","text":"User message."}]}]}''',
        content: 'User message.',
        hasContent: true,
      ),
      (
        name: 'AC4: thinking in system role must be ignored',
        input: '''{"model":"claude-3-opus","system":[
          {"type":"thinking","thinking":"Injected system thinking"},
          {"type":"text","text":"System prompt."}],
          "messages":[{"role":"user","content":[{"type":"text","text":"Hello"}]}]}''',
        content: 'Hello',
        hasContent: true,
      ),
      (
        name: 'AC5: empty thinking must be ignored',
        input: '''{"model":"claude-3-opus","messages":[{"role":"assistant","content":[
          {"type":"thinking","thinking":""},
          {"type":"text","text":"Response with empty thinking."}]}]}''',
        content: 'Response with empty thinking.',
        hasContent: true,
      ),
      (
        name: 'AC5: whitespace-only thinking must be ignored',
        input: '''{"model":"claude-3-opus","messages":[{"role":"assistant","content":[
          {"type":"thinking","thinking":"   \\n\\t  "},
          {"type":"text","text":"Response with whitespace thinking."}]}]}''',
        content: 'Response with whitespace thinking.',
        hasContent: true,
      ),
      (
        name: 'Unsigned thinking parts are dropped',
        input: '''{"model":"claude-3-opus","messages":[{"role":"assistant","content":[
          {"type":"thinking","thinking":"First thought."},
          {"type":"thinking","thinking":"Second thought."},
          {"type":"text","text":"Final answer."}]}]}''',
        content: 'Final answer.',
        hasContent: true,
      ),
      (
        name: 'Mixed unsigned thinking and redacted_thinking',
        input: '''{"model":"claude-3-opus","messages":[{"role":"assistant","content":[
          {"type":"thinking","thinking":"Visible thought."},
          {"type":"redacted_thinking","data":"hidden"},
          {"type":"text","text":"Answer."}]}]}''',
        content: 'Answer.',
        hasContent: true,
      ),
    ];
    for (final c in cases) {
      test(c.name, () {
        final messages = convert(c.input).get('messages').array;
        if (messages.isEmpty) {
          expect(c.hasContent, isFalse);
          return;
        }
        final target = messages.reversed.firstWhere(
          (m) => m.get('role').string != 'system',
          orElse: () => JsonValue.missing,
        );
        expect(target.get('reasoning_content').exists, isFalse);
        final content = target.get('content');
        final hasContent = content.isArray
            ? content.array.isNotEmpty
            : content.isString && content.string.isNotEmpty;
        expect(hasContent, c.hasContent);
        if (c.hasContent && c.content.isNotEmpty) {
          final text = content.array
              .firstWhere((v) => v.get('type').string == 'text')
              .get('text')
              .string;
          expect(text, c.content);
        }
      });
    }
  });

  group('signed thinking compatibility', () {
    final cases = [
      (
        'GPT-compatible signature keeps reasoning_content',
        validGptChatReasoningSignature(),
        'provider state',
        true,
      ),
      ('Claude signature drops reasoning_content', 'claude#EjQ=', '', false),
      (
        'Gemini signature drops reasoning_content',
        'gemini#EjQKMgEMOdbHO0Gd+c9Mxk4ELwPGbpCEcp2mFfYYLix2UVtBH3fL8GECc4+JITVnHF4qZDsA',
        '',
        false,
      ),
      (
        'Unknown signature drops reasoning_content',
        'not-a-provider-signature',
        '',
        false,
      ),
    ];
    for (final (name, signature, want, has) in cases) {
      test(name, () {
        final input = jsonEncode({
          'model': 'claude-3-opus',
          'messages': [
            {
              'role': 'assistant',
              'content': [
                {
                  'type': 'thinking',
                  'thinking': 'provider state',
                  'signature': signature,
                },
                {'type': 'text', 'text': 'visible answer'},
              ],
            },
          ],
        });
        final assistant = convert(input, model: 'gpt-5').get('messages.0');
        expect(assistant.get('reasoning_content').exists, has);
        expect(assistant.get('reasoning_content').string, want);
        expect(assistant.get('content.0.text').string, 'visible answer');
      });
    }
  });

  test('preserving thinking keeps unsigned reasoning', () {
    const input = '''{"messages":[{"role":"assistant","content":[
      {"type":"thinking","thinking":"kept"},{"type":"text","text":"answer"}]}]}''';
    final out = JsonValue(
      convertClaudeRequestToOpenAI('m', input, false, preserveThinking: true),
    );
    expect(out.get('messages.0.reasoning_content').string, 'kept');
  });

  test('unsigned thinking-only message is dropped', () {
    final out = convert('''{"model":"claude-3-opus","messages":[
      {"role":"user","content":[{"type":"text","text":"What is 2+2?"}]},
      {"role":"assistant","content":[{"type":"thinking","thinking":"Let me calculate: 2+2=4"}]},
      {"role":"user","content":[{"type":"text","text":"Thanks"}]}]}''');
    final messages = out.get('messages').array;
    expect(messages, hasLength(2));
    for (final message in messages) {
      expect(message.get('reasoning_content').exists, isFalse);
    }
  });

  test('message system role wraps as user reminder', () {
    final out = convert(
      '''{"model":"claude-sonnet-4-5",
      "system":[{"type":"text","text":"Top-level rules"}],
      "messages":[
        {"role":"user","content":[{"type":"text","text":"Hello"}]},
        {"role":"system","content":"String mid-conversation rule"},
        {"role":"assistant","content":[{"type":"text","text":"Hi there"}]},
        {"role":"system","content":[{"type":"text","text":"Array mid-conversation rule"}]},
        {"role":"user","content":[{"type":"text","text":"Follow up"}]}]}''',
      model: 'gpt-5',
    );
    final messages = out.get('messages').array;
    expect(messages, hasLength(6));
    expect(roles(out), ['system', 'user', 'user', 'assistant', 'user', 'user']);
    final system = messages[0].get('content').array;
    expect(system, hasLength(1));
    expect(system[0].get('text').string, 'Top-level rules');
    expect(
      messages[2].get('content.0.text').string,
      '<system-reminder>\nString mid-conversation rule\n</system-reminder>',
    );
    expect(
      messages[4].get('content.0.text').string,
      '<system-reminder>\nArray mid-conversation rule\n</system-reminder>',
    );
  });

  test('preserves tool adjacency with intervening system message', () {
    final out = convert('''{"model":"gpt-5","messages":[
      {"role":"user","content":[{"type":"text","text":"Execute tools"}]},
      {"role":"assistant","content":[
        {"type":"tool_use","id":"call_1","name":"tool_one","input":{"a":1}},
        {"type":"tool_use","id":"call_2","name":"tool_two","input":{"b":2}}]},
      {"role":"system","content":"Context update between tool call and tool result"},
      {"role":"user","content":[
        {"type":"tool_result","tool_use_id":"call_2","content":"result 2"},
        {"type":"tool_result","tool_use_id":"call_1","content":"result 1"},
        {"type":"text","text":"Now summarize"}]}]}''', model: 'gpt-5');
    final messages = out.get('messages').array;
    expect(roles(out), ['user', 'assistant', 'tool', 'tool', 'user', 'user']);
    expect(messages[2].get('tool_call_id').string, 'call_1');
    expect(messages[3].get('tool_call_id').string, 'call_2');
    expect(
      messages[4].get('content.0.text').string,
      '<system-reminder>\nContext update between tool call and tool result\n'
      '</system-reminder>',
    );
    expect(messages[5].get('content.0.text').string, 'Now summarize');
  });

  group('system message scenarios', () {
    final cases = [
      (
        'No system field',
        '{"model":"claude-3-opus","messages":[{"role":"user","content":"hello"}]}',
        false,
        '',
      ),
      (
        'Empty string system field',
        '{"model":"claude-3-opus","system":"","messages":[{"role":"user","content":"hello"}]}',
        false,
        '',
      ),
      (
        'String system field',
        '{"model":"claude-3-opus","system":"Be helpful","messages":[{"role":"user","content":"hello"}]}',
        true,
        'Be helpful',
      ),
      (
        'Array system field with text',
        '{"model":"claude-3-opus","system":[{"type":"text","text":"Array system"}],"messages":[{"role":"user","content":"hello"}]}',
        true,
        'Array system',
      ),
      (
        'Array system field with multiple text blocks',
        '{"model":"claude-3-opus","system":[{"type":"text","text":"Block 1"},{"type":"text","text":"Block 2"}],"messages":[{"role":"user","content":"hello"}]}',
        true,
        'Block 2',
      ),
    ];
    for (final (name, input, hasSystem, text) in cases) {
      test(name, () {
        final messages = convert(input).get('messages').array;
        final first = messages.firstOrNull;
        final has = first != null && first.get('role').string == 'system';
        expect(has, hasSystem);
        if (hasSystem) {
          final content = first!.get('content');
          final got = content.isArray
              ? content.array.last.get('text').string
              : content.string;
          expect(got, text);
        }
      });
    }
  });

  test('tool schema adds missing object properties', () {
    final out = convert('''{"model":"claude-3-opus","tools":[
      {"name":"empty_params","description":"No args","input_schema":{"type":"object"}},
      {"name":"nested_params","description":"Nested args","input_schema":{"type":"object",
        "properties":{"nested":{"type":"object"},
          "items":{"type":"array","items":{"type":"object"}}}}}],
      "messages":[{"role":"user","content":"hello"}]}''');
    expect(out.get('tools.0.function.parameters.properties').isObject, isTrue);
    expect(
      out
          .get('tools.1.function.parameters.properties.nested.properties')
          .isObject,
      isTrue,
    );
    expect(
      out
          .get('tools.1.function.parameters.properties.items.items.properties')
          .isObject,
      isTrue,
    );
  });

  test('tool result order and content', () {
    final out = convert('''{"model":"claude-3-opus","messages":[
      {"role":"assistant","content":[{"type":"tool_use","id":"call_1","name":"do_work","input":{"a":1}}]},
      {"role":"user","content":[
        {"type":"text","text":"before"},
        {"type":"tool_result","tool_use_id":"call_1","content":[{"type":"text","text":"tool ok"}]},
        {"type":"text","text":"after"}]}]}''');
    final messages = out.get('messages').array;
    expect(messages, hasLength(3));
    expect(messages[0].get('role').string, 'assistant');
    expect(messages[0].get('tool_calls').exists, isTrue);
    expect(messages[1].get('role').string, 'tool');
    expect(messages[1].get('tool_call_id').string, 'call_1');
    expect(messages[1].get('content').string, 'tool ok');
    expect(messages[2].get('role').string, 'user');
    expect(messages[2].get('content.0.text').string, 'before');
    expect(messages[2].get('content.1.text').string, 'after');
  });

  test('tool result object content', () {
    final out = convert(
      '''{"model":"claude-3-opus","messages":[
      {"role":"assistant","content":[{"type":"tool_use","id":"call_1","name":"do_work","input":{"a":1}}]},
      {"role":"user","content":[{"type":"tool_result","tool_use_id":"call_1","content":{"foo":"bar"}}]}]}''',
    );
    final messages = out.get('messages').array;
    expect(messages, hasLength(2));
    expect(messages[1].get('role').string, 'tool');
    expect(
      JsonValue.parse(messages[1].get('content').string).get('foo').string,
      'bar',
    );
  });

  test('tool result text and image content', () {
    final out = convert(
      '''{"model":"claude-3-opus","messages":[
      {"role":"assistant","content":[{"type":"tool_use","id":"call_1","name":"do_work","input":{"a":1}}]},
      {"role":"user","content":[{"type":"tool_result","tool_use_id":"call_1","content":[
        {"type":"text","text":"tool ok"},
        {"type":"image","source":{"type":"base64","media_type":"image/png","data":"iVBORw0KGgoAAAANSUhEUg=="}}]}]}]}''',
    );
    final messages = out.get('messages').array;
    expect(messages, hasLength(3));
    expect(messages[1].get('role').string, 'tool');
    expect(messages[1].get('content').isArray, isFalse);
    expect(messages[1].get('content').string, 'tool ok');
    final relay = messages[2];
    expect(relay.get('role').string, 'user');
    expect(relay.get('content').isArray, isTrue);
    expect(
      relay.get('content.0.text').string,
      'Images returned by the preceding tool call(s):',
    );
    expect(relay.get('content.1.type').string, 'image_url');
    expect(
      relay.get('content.1.image_url.url').string,
      'data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==',
    );
  });

  test('tool result URL image only', () {
    final out = convert(
      '''{"model":"claude-3-opus","messages":[
      {"role":"assistant","content":[{"type":"tool_use","id":"call_1","name":"do_work","input":{"a":1}}]},
      {"role":"user","content":[{"type":"tool_result","tool_use_id":"call_1","content":
        {"type":"image","source":{"type":"url","url":"https://example.com/tool.png"}}}]}]}''',
    );
    final messages = out.get('messages').array;
    expect(messages, hasLength(3));
    expect(messages[1].get('content').string, toolResultImagePlaceholder);
    expect(messages[2].get('role').string, 'user');
    expect(messages[2].get('content.1.type').string, 'image_url');
    expect(
      messages[2].get('content.1.image_url.url').string,
      'https://example.com/tool.png',
    );
  });

  test('tool result image merges into user text', () {
    final out = convert('''{"model":"claude-3-opus","messages":[
      {"role":"assistant","content":[{"type":"tool_use","id":"call_1","name":"screenshot","input":{}}]},
      {"role":"user","content":[
        {"type":"tool_result","tool_use_id":"call_1","content":[
          {"type":"image","source":{"type":"base64","media_type":"image/png","data":"iVBORw0KGgoAAAANSUhEUg=="}}]},
        {"type":"text","text":"What color?"}]}]}''');
    final messages = out.get('messages').array;
    expect(messages, hasLength(3));
    expect(messages[2].get('role').string, 'user');
    final content = messages[2].get('content');
    expect(content.array, hasLength(3));
    expect(
      content.get('0.text').string,
      'Images returned by the preceding tool call(s):',
    );
    expect(content.get('1.type').string, 'image_url');
    expect(content.get('2.text').string, 'What color?');
  });

  test('multiple tool results with images', () {
    final out = convert(
      '''{"model":"claude-3-opus","messages":[
      {"role":"assistant","content":[
        {"type":"tool_use","id":"call_1","name":"shot1","input":{}},
        {"type":"tool_use","id":"call_2","name":"shot2","input":{}}]},
      {"role":"user","content":[
        {"type":"tool_result","tool_use_id":"call_1","content":[
          {"type":"text","text":"result 1"},
          {"type":"image","source":{"type":"base64","media_type":"image/png","data":"img1"}}]},
        {"type":"tool_result","tool_use_id":"call_2","content":
          {"type":"image","source":{"type":"url","url":"https://example.com/2.png"}}}]}]}''',
    );
    final messages = out.get('messages').array;
    expect(messages, hasLength(4));
    expect(messages[1].get('role').string, 'tool');
    expect(messages[1].get('tool_call_id').string, 'call_1');
    expect(messages[1].get('content').string, 'result 1');
    expect(messages[2].get('role').string, 'tool');
    expect(messages[2].get('tool_call_id').string, 'call_2');
    expect(messages[2].get('content').string, toolResultImagePlaceholder);
    expect(messages[3].get('role').string, 'user');
    final relay = messages[3].get('content').array;
    expect(relay, hasLength(3));
    expect(
      relay[0].get('text').string,
      'Images returned by the preceding tool call(s):',
    );
    expect(relay[1].get('image_url.url').string, 'data:image/png;base64,img1');
    expect(relay[2].get('image_url.url').string, 'https://example.com/2.png');
  });

  test('assistant text, tool use, text order', () {
    final out = convert(
      '''{"model":"claude-3-opus","messages":[{"role":"assistant","content":[
      {"type":"text","text":"pre"},
      {"type":"tool_use","id":"call_1","name":"do_work","input":{"a":1}},
      {"type":"text","text":"post"}]}]}''',
    );
    final messages = out.get('messages').array;
    expect(messages, hasLength(1));
    final assistant = messages[0];
    expect(assistant.get('role').string, 'assistant');
    expect(assistant.get('tool_calls').exists, isTrue);
    expect(assistant.get('tool_calls.0.id').string, 'call_1');
    expect(assistant.get('tool_calls.0.function.name').string, 'do_work');
    expect(
      JsonValue.parse(assistant.get('tool_calls.0.function.arguments').string)
          .get('a')
          .integer,
      1,
    );
    expect(assistant.get('content.0.text').string, 'pre');
    expect(assistant.get('content.1.text').string, 'post');
  });

  test('assistant thinking, tool use, thinking split', () {
    final out = convert(
      '''{"model":"claude-3-opus","messages":[{"role":"assistant","content":[
      {"type":"thinking","thinking":"t1"},
      {"type":"text","text":"pre"},
      {"type":"tool_use","id":"call_1","name":"do_work","input":{"a":1}},
      {"type":"thinking","thinking":"t2"},
      {"type":"text","text":"post"}]}]}''',
    );
    final messages = out.get('messages').array;
    expect(messages, hasLength(1));
    final assistant = messages[0];
    expect(assistant.get('role').string, 'assistant');
    expect(assistant.get('content.0.text').string, 'pre');
    expect(assistant.get('content.1.text').string, 'post');
    expect(assistant.get('tool_calls').exists, isTrue);
    expect(assistant.get('reasoning_content').exists, isFalse);
  });

  test('strips Claude Code attribution', () {
    final out = convert(
      '''{"model":"claude-sonnet-4-5","system":[
      {"type":"text","text":"x-anthropic-billing-header: cc_version=2.1.63.abc; cc_entrypoint=cli; cch=12345;"},
      {"type":"text","text":"User system prompt"}],
      "messages":[{"role":"user","content":[{"type":"text","text":"hi"}]}]}''',
      model: 'gpt-5',
    );
    final messages = out.get('messages').array;
    expect(messages.first.get('role').string, 'system');
    final content = messages.first.get('content').array;
    expect(content, hasLength(1));
    expect(content[0].get('text').string, 'User system prompt');
  });

  group('stop sequences', () {
    for (final (name, stops) in [
      ('single stop sequence is emitted as array', ['</block>']),
      ('multiple stop sequences are emitted as array', ['stop1', 'stop2']),
    ]) {
      test(name, () {
        final out = convert(
          jsonEncode({
            'model': 'claude-3-opus',
            'stop_sequences': stops,
            'messages': [
              {'role': 'user', 'content': 'hi'},
            ],
          }),
          model: 'gpt-4o',
        );
        final stop = out.get('stop');
        expect(stop.isArray, isTrue);
        expect([for (final item in stop.array) item.string], stops);
      });
    }
  });

  test('tool without input schema defaults parameters', () {
    final out = convert('''{"model":"claude-opus-5","tools":[
      {"type":"web_search_20250305","name":"web_search","max_uses":8},
      {"name":"no_schema_custom"},
      {"name":"null_schema_custom","input_schema":null}],
      "messages":[{"role":"user","content":"hello"}]}''');
    for (final (i, name) in [
      'web_search',
      'no_schema_custom',
      'null_schema_custom',
    ].indexed) {
      final function = out.get('tools.$i.function');
      expect(function.get('name').string, name);
      final params = function.get('parameters');
      expect(params.exists, isTrue);
      expect(params.get('type').string, 'object');
      expect(params.get('properties').isObject, isTrue);
    }
  });

  test('strips unsupported Unicode property escape patterns', () {
    final input = jsonEncode({
      'model': 'gpt-5.6',
      'messages': [
        {'role': 'user', 'content': 'hello'},
      ],
      'tools': [
        {
          'name': 'Artifact',
          'description': 'Render an HTML file to an Artifact',
          'input_schema': {
            'type': 'object',
            'properties': {
              'field': {
                'type': 'string',
                'description': 'field to replace',
                'pattern':
                    r'^(?!__.*__$)[^\p{Cc}\p{Cf}\p{Zl}\p{Zp}"\\./[\]]{1,200}$',
              },
              'asset_id': {'type': 'string', 'pattern': r'^[0-9a-f]{32}$'},
              'lookahead_safe': {
                'type': 'string',
                'pattern': r'^(?!__.*__$).{1,200}$',
              },
            },
          },
        },
      ],
    });
    final params = convert(
      input,
      model: 'gpt-5.6',
    ).get('tools.0.function.parameters');
    expect(params.exists, isTrue);
    expect(params.get('properties.field.pattern').exists, isFalse);
    expect(params.get('properties.field.type').string, 'string');
    expect(params.get('properties.asset_id.pattern').string, r'^[0-9a-f]{32}$');
    expect(
      params.get('properties.lookahead_safe.pattern').string,
      r'^(?!__.*__$).{1,200}$',
    );
  });

  test('preserves non-schema pattern keys', () {
    final input = jsonEncode({
      'model': 'gpt-5.6',
      'messages': [
        {'role': 'user', 'content': 'hello'},
      ],
      'tools': [
        {
          'name': 'config_tool',
          'input_schema': {
            'type': 'object',
            'properties': {
              'regex_config': {
                'type': 'object',
                'default': {'pattern': r'\p{L}+'},
                'enum': [
                  {'pattern': r'\p{N}+'},
                ],
              },
              'real_schema': {'type': 'string', 'pattern': r'\p{L}+'},
            },
          },
        },
      ],
    });
    final params = convert(
      input,
      model: 'gpt-5.6',
    ).get('tools.0.function.parameters');
    expect(params.get('properties.real_schema.pattern').exists, isFalse);
    expect(
      params.get('properties.regex_config.default.pattern').string,
      r'\p{L}+',
    );
    expect(
      params.get('properties.regex_config.enum.0.pattern').string,
      r'\p{N}+',
    );
  });

  test('strips patternProperties incompatible keys', () {
    final input = jsonEncode({
      'model': 'gpt-5.6',
      'messages': [
        {'role': 'user', 'content': 'hello'},
      ],
      'tools': [
        {
          'name': 'pattern_tool',
          'input_schema': {
            'type': 'object',
            'patternProperties': {
              r'^\p{L}+$': {'type': 'string'},
              r'^[a-z]+$': {'type': 'number'},
            },
          },
        },
      ],
    });
    final props = convert(
      input,
      model: 'gpt-5.6',
    ).get('tools.0.function.parameters.patternProperties').map;
    expect(props.containsKey(r'^\p{L}+$'), isFalse);
    expect(props.containsKey(r'^[a-z]+$'), isTrue);
  });

  test('tool result preserves function name', () {
    final out = convert(
      '''{"model":"gemini-3.8-flash","max_tokens":64,"tools":[
      {"name":"get_weather","description":"Get weather","input_schema":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}},
      {"name":"get_time","description":"Get time","input_schema":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}}],
      "messages":[
        {"role":"user","content":"What's the weather and time in Jakarta?"},
        {"role":"assistant","content":[
          {"type":"tool_use","id":"toolu_01ABC","name":"get_weather","input":{"city":"Jakarta"}},
          {"type":"tool_use","id":"toolu_02DEF","name":"get_time","input":{"city":"Jakarta"}}]},
        {"role":"user","content":[
          {"type":"tool_result","tool_use_id":"toolu_01ABC","content":"32C, humid"},
          {"type":"tool_result","tool_use_id":"toolu_02DEF","content":"12:00 PM"}]}]}''',
      model: 'gemini-3.8-flash',
    );
    final tools = [
      for (final m in out.get('messages').array)
        if (m.get('role').string == 'tool') m,
    ];
    expect(tools, hasLength(2));
    expect(tools[0].get('tool_call_id').string, 'toolu_01ABC');
    expect(tools[0].get('name').string, 'get_weather');
    expect(tools[0].get('content').string, '32C, humid');
    expect(tools[1].get('tool_call_id').string, 'toolu_02DEF');
    expect(tools[1].get('name').string, 'get_time');
    expect(tools[1].get('content').string, '12:00 PM');
  });

  test('tool result with unknown id has no name', () {
    final tool = convert(
      '''{"model":"gemini-3.8-flash","messages":[{"role":"user","content":[
      {"type":"tool_result","tool_use_id":"orphan_call_1","content":"result"}]}]}''',
    ).get('messages.0');
    expect(tool.get('role').string, 'tool');
    expect(tool.get('tool_call_id').string, 'orphan_call_1');
    expect(tool.get('name').exists, isFalse);
  });

  test('tool call pairing by id', () {
    final out = convert(
      '''{"model":"deepseek-v4.1-flash","messages":[
      {"role":"user","content":[{"type":"text","text":"Run analysis"}]},
      {"role":"assistant","content":[
        {"type":"tool_use","id":"call_1","name":"fetch_data","input":{"id":123}},
        {"type":"tool_use","id":"call_2","name":"calc_metric","input":{"scale":1.5}}]},
      {"role":"assistant","content":[
        {"type":"text","text":"Waiting for results to continue"},
        {"type":"thinking","thinking":"Thinking about next steps","signature":"sig_abc"}]},
      {"role":"user","content":[{"type":"text","text":"Reminder: keep timeout short"}]},
      {"role":"user","content":[
        {"type":"tool_result","tool_use_id":"call_2","content":"metric_ok"},
        {"type":"tool_result","tool_use_id":"call_1","content":"data_ok"}]}]}''',
      model: 'deepseek-v4.1-flash',
    );
    final messages = out.get('messages').array;
    expect(messages, hasLength(6));
    final got = roles(out);
    expect(got[1], 'assistant');
    expect(messages[1].get('tool_calls').exists, isTrue);
    expect(got[2], 'tool');
    expect(got[3], 'tool');
    expect(
      [
        messages[2].get('tool_call_id').string,
        messages[3].get('tool_call_id').string,
      ],
      ['call_2', 'call_1'],
    );
  });

  test('orphan and incomplete histories are left as they are', () {
    final out = convert(
      '''{"model":"deepseek-v4.1-flash","messages":[
      {"role":"user","content":[{"type":"text","text":"Start"}]},
      {"role":"assistant","content":[
        {"type":"tool_use","id":"call_alpha","name":"do_a","input":{}},
        {"type":"tool_use","id":"call_beta","name":"do_b","input":{}}]},
      {"role":"user","content":[{"type":"text","text":"Waiting on results"}]},
      {"role":"user","content":[{"type":"tool_result","tool_use_id":"call_unmatched","content":"orphan_result"}]}]}''',
      model: 'deepseek-v4.1-flash',
    );
    expect(out.get('messages').array, hasLength(4));
    expect(roles(out).sublist(1), ['assistant', 'user', 'tool']);
  });

  group('tool choice', () {
    String request(String choice) =>
        '''{"model":"gpt-5.4","max_tokens":64,
        "messages":[{"role":"user","content":"test"}],
        "tool_choice":$choice,
        "tools":[{"name":"tool_a","description":"test","input_schema":{"type":"object","properties":{}}},
                 {"name":"tool_b","description":"test","input_schema":{"type":"object","properties":{}}}]}''';

    test('none does not become auto', () {
      expect(
        convert(request('{"type":"none"}')).get('tool_choice').string,
        'none',
      );
    });

    test('disable_parallel_tool_use maps to parallel_tool_calls false', () {
      final parallel = convert(
        request('{"type":"auto","disable_parallel_tool_use":true}'),
      ).get('parallel_tool_calls');
      expect(parallel.exists, isTrue);
      expect(parallel.boolean, isFalse);
    });

    test('unknown tool_choice type fails closed to none', () {
      expect(
        convert(request('{"type":"unknown_future_restriction"}'))
            .get('tool_choice')
            .string,
        'none',
      );
    });

    test('tool choice with empty name fails closed to none', () {
      expect(
        convert(request('{"type":"tool","name":""}')).get('tool_choice').string,
        'none',
      );
    });

    test('tool_choice null does not set tool_choice', () {
      expect(convert(request('null')).get('tool_choice').exists, isFalse);
    });
  });

  group('enabled thinking effort', () {
    for (final (name, input, effort) in [
      (
        'explicit output_config effort is preserved without budget',
        '{"thinking":{"type":"enabled"},"output_config":{"effort":"high"}}',
        'high',
      ),
      (
        'legacy budget remains authoritative when both are present',
        '{"thinking":{"type":"enabled","budget_tokens":8192},"output_config":{"effort":"high"}}',
        'medium',
      ),
      (
        'enabled without budget or effort keeps auto default',
        '{"thinking":{"type":"enabled"}}',
        'auto',
      ),
      (
        'enabled with empty effort string falls back to auto',
        '{"thinking":{"type":"enabled"},"output_config":{"effort":""}}',
        'auto',
      ),
      (
        'enabled with whitespace-only effort falls back to auto',
        '{"thinking":{"type":"enabled"},"output_config":{"effort":"   "}}',
        'auto',
      ),
      (
        'enabled with non-string effort falls back to auto',
        '{"thinking":{"type":"enabled"},"output_config":{"effort":123}}',
        'auto',
      ),
    ]) {
      test(name, () {
        expect(convert(input).get('reasoning_effort').string, effort);
      });
    }
  });

  test('normalizes boolean subschemas', () {
    final params = convert(
      '''{"model":"claude-3-opus","tools":[{"name":"patch_tool",
      "description":"Applies a JSON patch","input_schema":{"type":"object",
        "properties":{
          "patch":{"type":"array","items":true},
          "anything":true,
          "disabled":false,
          "enabled_flag":{"type":"boolean","default":true,"enum":[true,false]},
          "either":{"anyOf":[true,{"type":"string"}]},
          "nested_obj":{"type":"object","properties":{"foo":{"type":"string"}},"additionalProperties":true}},
        "additionalProperties":false,
        "\$defs":{"wildcard":true}}}],
      "messages":[{"role":"user","content":"hello"}]}''',
    ).get('tools.0.function.parameters');
    expect(params.exists, isTrue);
    expect(params.get('properties.patch.items').raw, '{}');
    expect(params.get('properties.anything').raw, '{}');
    expect(params.get('properties.either.anyOf.0').raw, '{}');
    expect(params.get(r'$defs.wildcard').raw, '{}');
    expect(params.get('additionalProperties').type, JsonType.falsy);
    expect(
      params.get('properties.nested_obj.additionalProperties').type,
      JsonType.truthy,
    );
    expect(params.get('properties.disabled').type, JsonType.falsy);
    expect(params.get('properties.enabled_flag.default').type, JsonType.truthy);
    expect(params.get('properties.enabled_flag.enum.0').type, JsonType.truthy);
    expect(params.get('properties.enabled_flag.enum.1').type, JsonType.falsy);
  });
}
