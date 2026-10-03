// Ported from CLIProxyAPI's internal/util/claude_attribution_test.go,
// claude_schema_test.go, internal/translator/common/claude_messages_test.go,
// claude_system_test.go and internal/signature/gpt_validation_test.go,
// grok_validation_test.go (MIT License; see
// lib/models/proxy/translate/NOTICE.md): the cases for what was ported.
// Grok's Claude and Gemini probes are not ported, nor their tests.

import 'dart:convert';

import 'package:baocode/models/proxy/translate/common.dart';
import 'package:baocode/models/proxy/translate/json_value.dart';
import 'package:baocode/models/proxy/translate/signature.dart';
import 'package:baocode/models/proxy/translate/thinking.dart';
import 'package:baocode/models/proxy/translate/util.dart';
import 'package:flutter_test/flutter_test.dart';

String testGptReasoningSignature() {
  final payload = List<int>.filled(1 + 8 + 16 + 16 + 32, 0);
  payload[0] = 0x80;
  for (var i = 9; i < payload.length; i++) {
    payload[i] = i;
  }
  return base64Url.encode(payload).replaceAll('=', '');
}

void main() {
  group('isClaudeCodeAttributionSystemText', () {
    for (final (name, text, want) in [
      (
        'attribution block',
        'x-anthropic-billing-header: cc_version=2.1.63.abc; cc_entrypoint=cli; cch=12345;',
        true,
      ),
      (
        'leading whitespace',
        '\n\t x-anthropic-billing-header: cc_version=2.1.63.abc; cch=12345;',
        true,
      ),
      ('regular system prompt', 'You are helpful.', false),
      ('empty text', '', false),
    ]) {
      test(name, () => expect(isClaudeCodeAttributionSystemText(text), want));
    }
  });

  group('hasUnsupportedUnicodePropertyEscape', () {
    for (final (name, pattern, want) in [
      (
        'Artifact regex with \\p escapes',
        r'^(?!__.*__$)[^\p{Cc}\p{Cf}\p{Zl}\p{Zp}"\./[\]]{1,200}$',
        true,
      ),
      ('uppercase \\P', r'^\P{L}+$', true),
      ('escaped backslash before p', r'^\\p{Cc}$', false),
      ('three backslashes', r'^\\\p{Cc}$', true),
      ('four backslashes', r'^\\\\p{Cc}$', false),
      ('hex characters', r'^[0-9a-f]{32}$', false),
      ('negative lookahead', r'^(?!__.*__$).{1,200}$', false),
      ('backreference', r'^(a)\1$', false),
      ('octal NUL escape', r'^[^\0]*$', true),
      ('hex NUL escape', r'^[^\x00]*$', false),
      ('escaped backslash before zero', r'^\\0$', false),
      ('trailing single backslash', r'abc\', false),
      ('\\p without brace', r'\p', false),
      ('\\p and unclosed brace', r'\p{', true),
      ('empty string', '', false),
    ]) {
      test(
        name,
        () => expect(hasUnsupportedUnicodePropertyEscape(pattern), want),
      );
    }
  });

  test('systemReminderText', () {
    expect(
      systemReminderText('Please call a tool now.'),
      '<system-reminder>\nPlease call a tool now.\n</system-reminder>',
    );
  });

  group('alignClaudeToolResults', () {
    List<String> describe(JsonValue parts) => [
      for (final part in parts.array)
        part.get('type').string == 'tool_result'
            ? part.get('tool_use_id').string
            : part.get('text').string,
    ];

    test('reorders permuted results, keeping other slots', () {
      final aligned = alignClaudeToolResults(
        JsonValue.parse('''[
          {"type":"tool_result","tool_use_id":"call_2","content":"two"},
          {"type":"text","text":"extra user text"},
          {"type":"tool_result","tool_use_id":"call_1","content":"one"}]'''),
        ['call_1', 'call_2'],
      );
      expect(describe(aligned), ['call_1', 'extra user text', 'call_2']);

      final leading = alignClaudeToolResults(
        JsonValue.parse('''[
          {"type":"text","text":"leading text"},
          {"type":"tool_result","tool_use_id":"call_2","content":"two"},
          {"type":"tool_result","tool_use_id":"call_1","content":"one"}]'''),
        ['call_1', 'call_2'],
      );
      expect(describe(leading), ['leading text', 'call_1', 'call_2']);
    });

    test('unchanged when the count differs', () {
      final input = JsonValue.parse(
        '[{"type":"tool_result","tool_use_id":"call_1","content":"one"}]',
      );
      expect(
        alignClaudeToolResults(input, ['call_1', 'call_2']).raw,
        input.raw,
      );
    });

    test('unchanged when an id is unknown', () {
      final input = JsonValue.parse('''[
        {"type":"tool_result","tool_use_id":"call_unknown","content":"unknown"},
        {"type":"tool_result","tool_use_id":"call_1","content":"one"}]''');
      expect(
        alignClaudeToolResults(input, ['call_1', 'call_2']).raw,
        input.raw,
      );
    });

    test('unchanged for a non-array', () {
      final input = JsonValue.parse('"text content"');
      expect(alignClaudeToolResults(input, ['call_1']).raw, input.raw);
    });
  });

  group('GPT reasoning signatures', () {
    test('detects a GPT reasoning signature', () {
      expect(isValidGptReasoningSignature(testGptReasoningSignature()), isTrue);
    });

    test('rejects a Unicode ellipsis', () {
      final signature = testGptReasoningSignature();
      final polluted =
          '${signature.substring(0, 20)}…${signature.substring(20)}';
      expect(isValidGptReasoningSignature(polluted), isFalse);
    });

    test('a gpt# prefix is stripped', () {
      final signature = testGptReasoningSignature();
      expect(compatibleGptSignature('gpt#$signature'), signature);
      expect(compatibleGptSignature('claude#$signature'), isNull);
    });
  });

  group('Grok encrypted content', () {
    test('rejects provider cache prefixes', () {
      final body = base64
          .encode([for (var i = 0; i < 120; i++) (i * 37 + 11) % 256])
          .replaceAll('=', '');
      for (final prefix in [
        'claude#',
        'anthropic#',
        'gemini#',
        'openai#',
        'codex#',
      ]) {
        expect(
          isValidGrokEncryptedContent('$prefix$body'),
          isFalse,
          reason: prefix,
        );
      }
    });

    test('rejects foreign shapes', () {
      for (final sample in [
        '',
        'bad',
        ' opaque',
        'gAAAAABinvalid-gpt-shape',
        'abcd_efg',
        base64.encode(List.filled(minGrokEncryptedContentDecodedLength, 0xa5)),
      ]) {
        expect(isValidGrokEncryptedContent(sample), isFalse, reason: sample);
      }
    });

    test('rejects a low-entropy payload', () {
      final sample = base64
          .encode(List.filled(minGrokEncryptedContentDecodedLength, 0xa5))
          .replaceAll('=', '');
      expect(isValidGrokEncryptedContent(sample), isFalse);
    });

    test('rejects an invalid base64 length', () {
      expect(isValidGrokEncryptedContent('AAAAA'), isFalse);
    });

    test('byteEntropyRatio of a single byte is zero', () {
      expect(byteEntropyRatio([0xa5]), 0);
    });
  });

  group('thinking', () {
    for (final (budget, level) in [
      (-1, 'auto'),
      (0, 'none'),
      (512, 'minimal'),
      (1024, 'low'),
      (8192, 'medium'),
      (24576, 'high'),
      (32000, 'xhigh'),
    ]) {
      test(
        'budget $budget is $level',
        () => expect(convertBudgetToLevel(budget), level),
      );
    }

    test('parseSuffix', () {
      final suffixed = parseSuffix('gpt-5(high)');
      expect(
        (suffixed.modelName, suffixed.hasSuffix, suffixed.rawSuffix),
        ('gpt-5', true, 'high'),
      );
      final plain = parseSuffix('gpt-5');
      expect((plain.modelName, plain.hasSuffix), ('gpt-5', false));
    });
  });
}
