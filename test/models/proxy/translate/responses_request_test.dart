// Ported from CLIProxyAPI's
// internal/translator/codex/claude/codex_claude_request_test.go,
// noop_optimization_test.go and codex_claude_compat_test.go (MIT License;
// see lib/models/proxy/translate/NOTICE.md). The compat mode is not
// ported, so of the compat tests only what the default translation does
// is kept.

import 'dart:convert';

import 'package:baocode/models/proxy/translate/json_value.dart';
import 'package:baocode/models/proxy/translate/responses_request.dart';
import 'package:flutter_test/flutter_test.dart';

JsonValue convert(String input, {String model = 'test-model'}) =>
    JsonValue.parse(jsonEncode(convertClaudeRequestToResponses(model, input)));

List<JsonValue> inputs(JsonValue out) => out.get('input').array;

int countInputItemsByType(JsonValue out, String type) =>
    inputs(out).where((item) => item.get('type').string == type).length;

/// A GPT reasoning signature of the right shape: version 0x80, a
/// timestamp, an IV, one AES block and an HMAC, base64url.
String validCodexReasoningSignature() {
  final raw = List<int>.filled(1 + 8 + 16 + 16 + 32, 0);
  raw[0] = 0x80;
  raw[8] = 1;
  return base64Url.encode(raw);
}

const grokSignature =
    'HmlYdr2aCAqCYP/m9mr8PS6KOsdMs72FGDigmydR+Jsmuv8KX97yWPlbOwmXJgWn0CbHaCacdQD3+n5EvpgLfPNmafS3kdICBjRuDf4bzHy7uBiUhNVhqPtp/ee1y9q4imPE4LYgD1VZ4J+bp9mTeqA1+nC9Oue58CiNEMV9SVaGenCD+aBnVuSTzQhD32Y+68i6HLJW0Dx6ifaRfb8hxYtA/sPM+/FTvAMW11nRho5a2BBSkpnzfqqAz/e/vGJ77/bygpXM823QA9wL9i0X';

void main() {
  test('standard Responses request shape', () {
    final out = convert('{"messages":[{"role":"user","content":"hi"}]}');
    expect(out.get('model').string, 'test-model');
    expect(out.get('stream').boolean, isTrue);
    expect(out.get('store').boolean, isFalse);
    // No Codex-only fields.
    expect(out.get('instructions').exists, isFalse);
    expect(out.get('prompt_cache_key').exists, isFalse);
  });

  group('system message scenarios', () {
    final cases = [
      (
        name: 'no system field',
        input: '{"model":"claude-3-opus","messages":[{"role":"user","content":"hello"}]}',
        texts: <String>[],
      ),
      (
        name: 'empty string system field',
        input: '{"model":"claude-3-opus","system":"","messages":[{"role":"user","content":"hello"}]}',
        texts: <String>[],
      ),
      (
        name: 'string system field',
        input: '{"model":"claude-3-opus","system":"Be helpful","messages":[{"role":"user","content":"hello"}]}',
        texts: ['Be helpful'],
      ),
      (
        name: 'message system role does not become developer',
        input: '''{"model":"claude-3-opus","messages":[
          {"role":"system","content":"Follow the project instructions"},
          {"role":"user","content":"hello"}]}''',
        texts: <String>[],
      ),
      (
        name: 'array system field with filtered billing header',
        input: '''{"model":"claude-3-opus","system":[
          {"type":"text","text":"x-anthropic-billing-header: tenant-123"},
          {"type":"text","text":"Block 1"},
          {"type":"text","text":"Block 2"}],
          "messages":[{"role":"user","content":"hello"}]}''',
        texts: ['Block 1', 'Block 2'],
      ),
    ];
    for (final c in cases) {
      test(c.name, () {
        final items = inputs(convert(c.input));
        final hasDeveloper =
            items.isNotEmpty && items[0].get('role').string == 'developer';
        expect(hasDeveloper, c.texts.isNotEmpty);
        if (!hasDeveloper) return;
        final content = items[0].get('content').array;
        expect(content, hasLength(c.texts.length));
        for (final (i, text) in c.texts.indexed) {
          expect(content[i].get('type').string, 'input_text');
          expect(content[i].get('text').string, text);
        }
      });
    }
  });

  test('message system role wraps as user reminder', () {
    final items = inputs(
      convert('''{"model":"claude-3-opus",
        "system":[{"type":"text","text":"Top-level rules"}],
        "messages":[
          {"role":"user","content":"hello"},
          {"role":"system","content":"Follow the project instructions"},
          {"role":"assistant","content":[{"type":"text","text":"ok"}]},
          {"role":"system","content":[{"type":"text","text":"Use the current repo"}]}
        ]}'''),
    );
    expect(items, hasLength(5));
    expect(items[0].get('role').string, 'developer');
    expect(items[2].get('role').string, 'user');
    expect(
      items[2].get('content.0.text').string,
      '<system-reminder>\nFollow the project instructions\n</system-reminder>',
    );
    expect(items[4].get('role').string, 'user');
    expect(
      items[4].get('content.0.text').string,
      '<system-reminder>\nUse the current repo\n</system-reminder>',
    );
  });

  test('keeps tool adjacency with an intervening system message', () {
    final items = inputs(
      convert(model: 'gpt-5.4', '''{"model":"gpt-5.4","messages":[
        {"role":"user","content":[{"type":"text","text":"Execute tools"}]},
        {"role":"assistant","content":[
          {"type":"tool_use","id":"call_1","name":"tool_one","input":{"a":1}},
          {"type":"tool_use","id":"call_2","name":"tool_two","input":{"b":2}}]},
        {"role":"system","content":"Context update between tool call and tool result"},
        {"role":"user","content":[
          {"type":"tool_result","tool_use_id":"call_2","content":"result 2"},
          {"type":"tool_result","tool_use_id":"call_1","content":"result 1"},
          {"type":"text","text":"Now summarize"}]}
      ]}'''),
    );
    expect(
      [for (final item in items) item.get('type').string],
      [
        'message',
        'function_call',
        'function_call',
        'function_call_output',
        'function_call_output',
        'message',
        'message',
      ],
    );
    expect(items[3].get('call_id').string, 'call_1');
    expect(items[4].get('call_id').string, 'call_2');
    expect(
      items[5].get('content.0.text').string,
      '<system-reminder>\nContext update between tool call and tool result\n</system-reminder>',
    );
    expect(items[6].get('content.0.text').string, 'Now summarize');
  });

  group('parallel tool calls', () {
    final cases = [
      ('default true without disable_parallel_tool_use', '', true),
      (
        'disabled when the client opts out',
        '"tool_choice":{"disable_parallel_tool_use":true},',
        false,
      ),
      (
        'enabled when the client allows them',
        '"tool_choice":{"disable_parallel_tool_use":false},',
        true,
      ),
    ];
    for (final (name, choice, want) in cases) {
      test(name, () {
        final out = convert(
          '{"model":"claude-3-opus",$choice"messages":[{"role":"user","content":"hello"}]}',
        );
        expect(out.get('parallel_tool_calls').boolean, want);
      });
    }
  });

  group('service tier', () {
    final cases = [
      (
        name: 'priority passes through',
        tier: '"priority"',
        speed: '',
        want: 'priority',
      ),
      (
        name: 'fast tier normalizes to priority',
        tier: '"fast"',
        speed: '',
        want: 'priority',
      ),
      (
        name: 'unsupported tier is omitted',
        tier: '"default"',
        speed: '',
        want: null,
      ),
      (name: 'non-string tier is omitted', tier: 'true', speed: '', want: null),
      (
        name: 'fast speed maps to priority',
        tier: '',
        speed: '"fast"',
        want: 'priority',
      ),
      (
        name: 'standard speed is omitted',
        tier: '',
        speed: '"standard"',
        want: null,
      ),
      (
        name: 'non-string speed is omitted',
        tier: '',
        speed: 'true',
        want: null,
      ),
      (
        name: 'fast speed overrides unsupported tier',
        tier: '"auto"',
        speed: '"fast"',
        want: 'priority',
      ),
    ];
    for (final c in cases) {
      test(c.name, () {
        final out = convert(model: 'gpt-5.4', '''{"model":"gpt-5.4",
          ${c.tier.isEmpty ? '' : '"service_tier":${c.tier},'}
          ${c.speed.isEmpty ? '' : '"speed":${c.speed},'}
          "messages":[{"role":"user","content":"Reply with OK"}]}''');
        final tier = out.get('service_tier');
        expect(tier.exists, c.want != null);
        if (c.want != null) expect(tier.string, c.want);
      });
    }
  });

  test('shortens long tool_use ids', () {
    final longId = 'toolu_${'a' * 62}';
    final out = convert('''{"model":"claude-3-opus","messages":[
      {"role":"user","content":[{"type":"text","text":"run pwd"}]},
      {"role":"assistant","content":[{"type":"tool_use","id":"$longId","name":"Bash","input":{"cmd":"pwd"}}]},
      {"role":"user","content":[{"type":"tool_result","tool_use_id":"$longId","content":"ok"}]}
    ]}''');
    String callId(String type) =>
        inputs(out)
            .firstWhere((item) => item.get('type').string == type)
            .get('call_id')
            .string;
    final call = callId('function_call');
    expect(call, callId('function_call_output'));
    expect(call.length, lessThanOrEqualTo(64));
    expect(call, isNot(longId));
  });

  group('tool_choice mode mapping', () {
    for (final (claude, want) in [
      ('{"type":"any"}', 'required'),
      ('{"type":"none"}', 'none'),
      ('{"type":"auto"}', 'auto'),
    ]) {
      test('$claude → $want', () {
        final out = convert('''{"model":"claude-3-opus",
          "tools":[{"name":"lookup","description":"Lookup","input_schema":{"type":"object","properties":{}}}],
          "tool_choice":$claude,
          "messages":[{"role":"user","content":"hello"}]}''');
        expect(out.get('tool_choice').string, want);
      });
    }
  });

  test('specific tool_choice uses the converted name', () {
    const longName =
        'mcp__server_with_a_very_long_name_that_exceeds_sixty_four_characters__search';
    final out = convert('''{"model":"claude-3-opus",
      "tools":[{"name":"$longName","description":"Search","input_schema":{"type":"object","properties":{}}}],
      "tool_choice":{"type":"tool","name":"$longName"},
      "messages":[{"role":"user","content":"hello"}]}''');
    expect(out.get('tool_choice.type').string, 'function');
    expect(out.get('tool_choice.name').string, out.get('tools.0.name').string);
    expect(out.get('tool_choice.name').string, isNot(longName));
  });

  test('web search tool mapping', () {
    final out = convert('''{"model":"claude-3-opus",
      "tools":[{"type":"web_search_20260209","name":"web_search",
        "allowed_domains":["example.com"],"blocked_domains":["blocked.example"],
        "user_location":{"type":"approximate","city":"Beijing","country":"CN","timezone":"Asia/Shanghai"}}],
      "tool_choice":{"type":"tool","name":"web_search"},
      "messages":[{"role":"user","content":"hello"}]}''');
    expect(out.get('tools.0.type').string, 'web_search');
    expect(out.get('tools.0.filters.allowed_domains.0').string, 'example.com');
    expect(out.get('tools.0.blocked_domains').exists, isFalse);
    expect(out.get('tools.0.user_location.city').string, 'Beijing');
    expect(out.get('tool_choice.type').string, 'web_search');
  });

  test('web search tool_choice uses the declared typed tool name', () {
    final out = convert('''{"model":"claude-opus-4-7",
      "tools":[
        {"type":"web_search_20250305","name":"browser_search"},
        {"name":"web_search","description":"Local search","input_schema":{"type":"object","properties":{}}}],
      "tool_choice":{"type":"tool","name":"web_search"},
      "messages":[{"role":"user","content":"hello"}]}''');
    expect(out.get('tool_choice.type').string, 'function');
    expect(out.get('tool_choice.name').string, 'web_search');
  });

  test('assistant thinking signature becomes a reasoning item', () {
    final signature = validCodexReasoningSignature();
    final out = convert('''{"model":"claude-3-opus","messages":[
      {"role":"assistant","content":[
        {"type":"thinking","thinking":"visible summary must not be replayed","signature":"$signature"},
        {"type":"text","text":"visible answer"}]},
      {"role":"user","content":"continue"}]}''');
    final items = inputs(out);
    expect(items, hasLength(3));
    expect(items[0].get('type').string, 'reasoning');
    expect(items[0].get('encrypted_content').string, signature);
    expect(items[0].get('summary').raw, '[]');
    expect(items[0].get('content').raw, 'null');
    expect(items[1].get('role').string, 'assistant');
    expect(items[1].get('content.0.type').string, 'output_text');
    expect(items[1].get('content.0.text').string, 'visible answer');
    expect(out.raw, isNot(contains('visible summary must not be replayed')));
  });

  test('a model that does not think gets no reasoning', () {
    final signature = validCodexReasoningSignature();
    final out = JsonValue(
      convertClaudeRequestToResponses(
        'gpt-4.1',
        '''{"thinking":{"type":"enabled","budget_tokens":4096},"messages":[
          {"role":"assistant","content":[{"type":"thinking","thinking":"t","signature":"$signature"},{"type":"text","text":"a"}]},
          {"role":"user","content":"go on"}]}''',
        reasoning: false,
      ),
    );
    expect(countInputItemsByType(out, 'reasoning'), 0);
    expect(out.get('reasoning').exists, isFalse);
    expect(out.get('include').exists, isFalse);
  });

  test('keeps base64 PDF document content', () {
    final content = convert(
      model: 'gpt-5.6-sol',
      '''{"messages":[{"role":"user","content":[
      {"type":"text","text":"before"},
      {"type":"document","source":{"type":"base64","media_type":"application/pdf","data":"JVBERi0xLjQK"}},
      {"type":"text","text":"after"}]}]}''',
    ).get('input.0.content').array;
    expect(content, hasLength(3));
    expect(
      [for (final c in content) c.get('type').string],
      ['input_text', 'input_file', 'input_text'],
    );
    expect(content[0].get('text').string, 'before');
    expect(
      content[1].get('file_data').string,
      'data:application/pdf;base64,JVBERi0xLjQK',
    );
    expect(content[1].get('filename').string, 'document.pdf');
    expect(content[2].get('text').string, 'after');
  });

  test('keeps content order across tool and reasoning items', () {
    final signature = validCodexReasoningSignature();
    final items = inputs(
      convert(model: 'gpt-5.4', '''{"system":"system rules","messages":[
        {"role":"assistant","content":[
          {"type":"text","text":"before reasoning"},
          {"type":"thinking","signature":"$signature"},
          {"type":"text","text":"before tool"},
          {"type":"tool_use","id":"toolu_1","name":"lookup","input":{"query":"test"}},
          {"type":"text","text":"after tool"}]},
        {"role":"user","content":[
          {"type":"tool_result","tool_use_id":"toolu_1","content":[
            {"type":"text","text":"tool output"},
            {"type":"image","source":{"media_type":"image/png","data":"aW1hZ2U="}}]},
          {"type":"text","text":"continue"}]}],
        "tools":[{"name":"lookup","input_schema":{"type":"object"}}]}'''),
    );
    expect(
      [for (final item in items) item.get('type').string],
      [
        'message',
        'message',
        'reasoning',
        'message',
        'function_call',
        'message',
        'function_call_output',
        'message',
      ],
    );
    expect(items[1].get('content.0.text').string, 'before reasoning');
    expect(items[3].get('content.0.text').string, 'before tool');
    expect(items[5].get('content.0.text').string, 'after tool');
    expect(items[6].get('output.0.type').string, 'input_text');
    expect(
      items[6].get('output.1.image_url').string,
      'data:image/png;base64,aW1hZ2U=',
    );
    expect(items[7].get('content.0.text').string, 'continue');
  });

  String grokPayload({String model = ''}) => jsonEncode({
    if (model.isNotEmpty) 'model': model,
    'messages': [
      {
        'role': 'assistant',
        'content': [
          {
            'type': 'thinking',
            'thinking': 'summary',
            'signature': grokSignature,
          },
          {'type': 'text', 'text': 'answer'},
        ],
      },
      {'role': 'user', 'content': 'next'},
    ],
  });

  test('assistant Grok signature becomes a reasoning item', () {
    final reasoning = convert(
      model: 'grok-4.5',
      grokPayload(model: 'grok-4.5'),
    ).get('input.0');
    expect(reasoning.get('type').string, 'reasoning');
    expect(reasoning.get('encrypted_content').string, grokSignature);
  });

  for (final model in ['gpt-5.4', 'claude-sonnet-4-6']) {
    test('ignores a Grok signature for $model', () {
      expect(
        countInputItemsByType(
          convert(model: model, grokPayload()),
          'reasoning',
        ),
        0,
      );
    });
  }

  group('ignores non-Codex thinking signatures', () {
    test('user thinking even with a Codex-shaped signature', () {
      final out = convert(
        '''{"model":"claude-3-opus","messages":[{"role":"user","content":[
        {"type":"thinking","thinking":"user supplied thinking","signature":"${validCodexReasoningSignature()}"},
        {"type":"text","text":"hello"}]}]}''',
      );
      expect(countInputItemsByType(out, 'reasoning'), 0);
    });

    test('Anthropic native signature', () {
      final out = convert(
        '''{"model":"claude-3-opus","messages":[{"role":"assistant","content":[
        {"type":"thinking","thinking":"anthropic thinking","signature":"Eo8Canthropic-state"},
        {"type":"text","text":"visible answer"}]}]}''',
      );
      expect(countInputItemsByType(out, 'reasoning'), 0);
    });

    test('empty signature', () {
      final out = convert(
        '{"messages":[{"role":"assistant","content":[{"type":"thinking","thinking":"reason","signature":""}]}]}',
        model: 'deepseek-v4',
      );
      expect(out.get('input.#').integer, 0);
    });

    test('unknown signature', () {
      final out = convert(
        '{"messages":[{"role":"assistant","content":[{"type":"thinking","thinking":"reason","signature":"opaque-encrypted-reasoning-token-xyz"}]}]}',
        model: 'deepseek-v4',
      );
      expect(out.get('input.#').integer, 0);
    });
  });

  group('output_config format', () {
    test('valid json_schema format', () {
      final out = convert(
        model: 'gpt-5.4',
        '''{"model":"gpt-5.4","max_tokens":128,
        "messages":[{"role":"user","content":"Return an object with one string field named answer."}],
        "output_config":{"format":{"type":"json_schema","schema":{
          "type":"object","properties":{"answer":{"type":"string"}},
          "required":["answer"],"additionalProperties":false}}}}''',
      );
      expect(out.get('text.format').exists, isTrue);
      expect(out.get('text.format.type').string, 'json_schema');
      expect(out.get('text.format.name').string, 'cli_proxy_structured_output');
      expect(out.get('text.format.strict').boolean, isTrue);
      expect(
        out.get('text.format.schema.properties.answer.type').string,
        'string',
      );
    });

    test('custom name and strict false', () {
      final out = convert(
        model: 'gpt-5.4',
        '''{"model":"gpt-5.4",
        "messages":[{"role":"user","content":"hello"}],
        "output_config":{"format":{"type":"json_schema","name":"custom_schema","strict":false,"schema":{"type":"object"}}}}''',
      );
      expect(out.get('text.format.name').string, 'custom_schema');
      expect(out.get('text.format.strict').boolean, isFalse);
    });

    test('no output_config.format', () {
      final out = convert(
        model: 'gpt-5.4',
        '{"model":"gpt-5.4","messages":[{"role":"user","content":"hello"}]}',
      );
      expect(out.get('text.format').exists, isFalse);
    });

    test('effort only', () {
      final out = convert(
        model: 'gpt-5.4',
        '''{"model":"gpt-5.4","thinking":{"type":"adaptive"},
        "output_config":{"effort":"high"},"messages":[{"role":"user","content":"hello"}]}''',
      );
      expect(out.get('text.format').exists, isFalse);
      expect(out.get('reasoning.effort').string, 'high');
    });

    test('an optional property downgrades strict', () {
      final out = convert(model: 'gpt-5.4', '''{"model":"gpt-5.4",
        "messages":[{"role":"user","content":"hello"}],
        "output_config":{"format":{"type":"json_schema","name":"cli_proxy_structured_output","strict":true,"schema":{
          "type":"object","properties":{"answer":{"type":"string"},"impossible":{"type":"string"}},
          "required":["answer"],"additionalProperties":false}}}}''');
      expect(out.get('text.format.strict').boolean, isFalse);
      expect(out.get('text.format.name').string, 'cli_proxy_structured_output');
    });

    test('fully required keeps strict', () {
      final out = convert(model: 'gpt-5.4', '''{"model":"gpt-5.4",
        "messages":[{"role":"user","content":"hello"}],
        "output_config":{"format":{"type":"json_schema","schema":{
          "type":"object","properties":{"answer":{"type":"string"}},
          "required":["answer"],"additionalProperties":false}}}}''');
      expect(out.get('text.format.strict').boolean, isTrue);
    });
  });

  group('normalizeToolParameters', () {
    test('strips nested \$schema and \$id', () {
      final out = JsonValue.parse(
        normalizeToolParameters(
          JsonValue.parse(r'''{
            "type":"object",
            "$schema":"http://json-schema.org/draft-07/schema#",
            "$id":"https://example.invalid/root",
            "properties":{
              "q":{"type":"string","$schema":"http://json-schema.org/draft-07/schema#","$id":"https://example.invalid/q"},
              "tags":{"type":"array","items":{"type":"string","$id":"https://example.invalid/tag"}},
              "mode":{"anyOf":[{"type":"string","$schema":"http://json-schema.org/draft-07/schema#"},{"type":"null"}]},
              "refField":{"$ref":"#/$defs/hint"}},
            "$defs":{"hint":{"type":"string","$id":"https://example.invalid/hint"}},
            "required":["q"]}'''),
        ),
      );
      for (final path in [
        r'$schema',
        r'$id',
        r'properties.q.$schema',
        r'properties.q.$id',
        r'properties.tags.items.$id',
        r'properties.mode.anyOf.0.$schema',
        r'$defs.hint.$id',
      ]) {
        expect(out.get(path).exists, isFalse, reason: path);
      }
      expect(out.get(r'properties.refField.$ref').string, r'#/$defs/hint');
      expect(out.get('properties.q.type').string, 'string');
    });

    test('keeps property names and literal data', () {
      final out = JsonValue.parse(
        normalizeToolParameters(
          JsonValue.parse(r'''{"type":"object","properties":{
            "$schema":{"type":"string","$schema":"http://json-schema.org/draft-07/schema#","$id":"https://example.invalid/sub-schema"},
            "$id":{"type":"string"},
            "config":{"type":"object","default":{"$id":"default-id-123"}}}}'''),
        ),
      );
      expect(out.get(r'properties.$schema').exists, isTrue);
      expect(out.get(r'properties.$schema.$schema').exists, isFalse);
      expect(out.get(r'properties.$schema.$id').exists, isFalse);
      expect(out.get(r'properties.$id').exists, isTrue);
      expect(
        out.get(r'properties.config.default.$id').string,
        'default-id-123',
      );

      const empty = '{"type":"object","properties":{}}';
      expect(normalizeToolParameters(JsonValue.missing), empty);
      expect(normalizeToolParameters(JsonValue.parse('null')), empty);

      final union = JsonValue.parse(
        normalizeToolParameters(JsonValue.parse('{"type":["object","null"]}')),
      );
      expect(
        [for (final t in union.get('type').array) t.string],
        ['object', 'null'],
      );
      expect(union.get('properties').exists, isTrue);
    });
  });

  test('strips nested tool schema meta', () {
    final params = convert(model: 'gpt-5', r'''{"model":"gpt-5",
      "messages":[{"role":"user","content":"hi"}],
      "tools":[{"name":"lookup","description":"Lookup","input_schema":{
        "type":"object",
        "$schema":"http://json-schema.org/draft-07/schema#",
        "properties":{
          "q":{"type":"string","$schema":"http://json-schema.org/draft-07/schema#","$id":"https://example.invalid/q"},
          "tags":{"type":"array","items":{"type":"string","$id":"https://example.invalid/tag"}},
          "mode":{"anyOf":[{"type":"string","$schema":"http://json-schema.org/draft-07/schema#"},{"type":"null"}]}},
        "$defs":{"hint":{"type":"string","$id":"https://example.invalid/hint"}},
        "required":["q"]}}]}''').get('tools.0.parameters');
    for (final path in [
      r'$schema',
      r'properties.q.$schema',
      r'properties.q.$id',
      r'properties.tags.items.$id',
      r'properties.mode.anyOf.0.$schema',
      r'$defs.hint.$id',
    ]) {
      expect(params.get(path).exists, isFalse, reason: path);
    }
  });

  test('strips unsupported Unicode property escape patterns', () {
    final params = convert(model: 'gpt-5.6', r'''{"model":"gpt-5.6",
      "messages":[{"role":"user","content":"hello"}],
      "tools":[{"name":"Artifact","description":"Render an HTML file to an Artifact","input_schema":{
        "type":"object",
        "properties":{
          "field":{"type":"string","description":"field to replace","pattern":"^(?!__.*__$)[^\\p{Cc}\\p{Cf}\\p{Zl}\\p{Zp}\"\\\\./[\\]]{1,200}$"},
          "asset_id":{"type":"string","pattern":"^[0-9a-f]{32}$"},
          "lookahead_safe":{"type":"string","pattern":"^(?!__.*__$).{1,200}$"},
          "literal_p":{"type":"string","pattern":"^\\\\p{Cc}$"},
          "nested":{"type":"object","properties":{"inner_field":{"type":"string","pattern":"\\P{L}+"}}},
          "union_field":{"anyOf":[{"type":"string","pattern":"\\p{N}+"},{"type":"null"}]}},
        "required":["field"]}}]}''').get('tools.0.parameters');
    expect(params.get('properties.field.pattern').exists, isFalse);
    expect(params.get('properties.field.type').string, 'string');
    expect(
      params.get('properties.field.description').string,
      'field to replace',
    );
    expect(params.get('properties.asset_id.pattern').string, r'^[0-9a-f]{32}$');
    expect(
      params.get('properties.lookahead_safe.pattern').string,
      r'^(?!__.*__$).{1,200}$',
    );
    expect(params.get('properties.literal_p.pattern').string, r'^\\p{Cc}$');
    expect(
      params.get('properties.nested.properties.inner_field.pattern').exists,
      isFalse,
    );
    expect(
      params.get('properties.nested.properties.inner_field.type').string,
      'string',
    );
    expect(
      params.get('properties.union_field.anyOf.0.pattern').exists,
      isFalse,
    );
    expect(params.get('required.0').string, 'field');
  });

  test('strips patternProperties keys upstream cannot compile', () {
    final params = convert(model: 'gpt-5.6', r'''{"model":"gpt-5.6",
      "messages":[{"role":"user","content":"hello"}],
      "tools":[{"name":"pattern_tool","input_schema":{"type":"object","patternProperties":{
        "^\\\\p{L}+$":{"type":"string"},
        "^[a-z]+$":{"type":"number"}}}}]}''').get('tools.0.parameters');
    final keys = params.get('patternProperties').map.keys;
    expect(keys, isNot(contains(r'^\p{L}+$')));
    expect(keys, contains(r'^[a-z]+$'));
  });

  test('normalizes a non-string tool name', () {
    final name = convert(
      model: 'gpt-test',
      '{"messages":[],"tools":[{"name":123,"input_schema":{"type":"object"}}]}',
    ).get('tools.0.name');
    expect(name.isString, isTrue);
    expect(name.string, '123');
  });
}
