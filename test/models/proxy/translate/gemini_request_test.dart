import 'dart:convert';

import 'package:baocode/models/proxy/translate/antigravity_request.dart';
import 'package:baocode/models/proxy/translate/antigravity_response.dart';
import 'package:baocode/models/proxy/translate/antigravity_signature.dart';
import 'package:baocode/models/proxy/translate/gemini_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('convertClaudeRequestToGemini', () {
    test('sends a bare generateContent payload without envelope or cloak', () {
      final out = convertClaudeRequestToGemini({
        'model': 'gemini-2.5-pro',
        'stream': true,
        'max_tokens': 4096,
        'temperature': 0.3,
        'top_p': 0.9,
        'top_k': 40,
        'stop_sequences': ['END'],
        'system': [
          {'type': 'text', 'text': 'You are Claude Code.'},
        ],
        'messages': [
          {'role': 'user', 'content': 'Read CLAUDE.md'},
        ],
      }, model: 'gemini-2.5-pro');
      expect(out.containsKey('model'), isFalse);
      expect(out.containsKey('stream'), isFalse);
      expect(out.containsKey('sessionId'), isFalse);
      expect(out['systemInstruction'], {
        'parts': [
          {'text': 'You are Claude Code.'},
        ],
      });
      expect(out['contents'], [
        {
          'role': 'user',
          'parts': [
            {'text': 'Read CLAUDE.md'},
          ],
        },
      ]);
      expect(out['generationConfig'], {
        'maxOutputTokens': 4096,
        'temperature': 0.3,
        'topP': 0.9,
        'topK': 40,
        'stopSequences': ['END'],
      });
    });

    test('translates function declarations with parametersJsonSchema and '
        'round-trips thoughtSignature and error/output tool results', () {
      final store = MemorySignatureStore();
      final signed = signedToolId('call_1', 'sig-abc', store);
      final out = convertClaudeRequestToGemini(
        {
          'messages': [
            {'role': 'user', 'content': 'run two tools'},
            {
              'role': 'assistant',
              'content': [
                {'type': 'thinking', 'thinking': 'ignored cross-model thought'},
                {
                  'type': 'tool_use',
                  'id': signed,
                  'name': '1st-tool',
                  'input': {'path': 'a.dart'},
                },
                {
                  'type': 'tool_use',
                  'id': 'call_2',
                  'name': 'Bash',
                  'input': {'cmd': 'ls'},
                },
              ],
            },
            {
              'role': 'user',
              'content': [
                {'type': 'tool_result', 'tool_use_id': signed, 'content': 'ok'},
                // Duplicate answer is dropped.
                {
                  'type': 'tool_result',
                  'tool_use_id': signed,
                  'content': 'duplicate',
                },
                {
                  'type': 'tool_result',
                  'tool_use_id': 'call_2',
                  'is_error': true,
                  'content': 'boom',
                },
                {'type': 'text', 'text': 'now explain'},
              ],
            },
          ],
          'tools': [
            {
              'name': '1st-tool',
              'description': 'Reads file',
              'input_schema': {
                'type': 'object',
                'properties': {
                  'path': {'type': 'string'},
                },
                'additionalProperties': false,
              },
            },
            {
              'name': 'DeferredToolPlaceholder',
              'input_schema': {'type': 'object'},
            },
          ],
          'tool_choice': {'type': 'tool', 'name': '1st-tool'},
        },
        model: 'gemini-3-pro',
        store: store,
      );

      final contents = out['contents'] as List;
      expect(contents, hasLength(4));
      final modelParts = (contents[1] as Map)['parts'] as List;
      expect(modelParts, [
        {
          'functionCall': {
            'name': '_x_1st-tool',
            'args': {'path': 'a.dart'},
            'id': 'call_1',
          },
          'thoughtSignature': 'sig-abc',
        },
        // Sibling call in a signed step gets no thoughtSignature.
        {
          'functionCall': {
            'name': 'Bash',
            'args': {'cmd': 'ls'},
            'id': 'call_2',
          },
        },
      ]);
      // Function responses stay in their own user turn; trailing user text
      // goes to a following user turn.
      expect(contents[2], {
        'role': 'user',
        'parts': [
          {
            'functionResponse': {
              'name': '_x_1st-tool',
              'id': 'call_1',
              'response': {'output': 'ok'},
            },
          },
          {
            'functionResponse': {
              'name': 'Bash',
              'id': 'call_2',
              'response': {'error': 'boom'},
            },
          },
        ],
      });
      expect(contents[3], {
        'role': 'user',
        'parts': [
          {'text': 'now explain'},
        ],
      });

      expect(out['tools'], [
        {
          'functionDeclarations': [
            {
              'name': '_x_1st-tool',
              'description': 'Reads file',
              'parametersJsonSchema': {
                'type': 'object',
                'properties': {
                  'path': {'type': 'string'},
                },
                'additionalProperties': false,
              },
            },
          ],
        },
      ]);
      expect(out['toolConfig'], {
        'functionCallingConfig': {
          'mode': 'ANY',
          'allowedFunctionNames': ['_x_1st-tool'],
        },
      });
    });

    test('injects skipThoughtSignature for unsigned tool calls and '
        'synthesizes interrupted responses', () {
      final out = convertClaudeRequestToGemini({
        'messages': [
          {
            'role': 'assistant',
            'content': [
              {
                'type': 'tool_use',
                'id': 'u1',
                'name': 'Read',
                'input': {'file': 'x'},
              },
            ],
          },
        ],
      }, model: 'gemini-3-flash');
      final contents = out['contents'] as List;
      // Leading user turn added, interrupted response paired, ends on user.
      expect(contents[0]['role'], 'user');
      expect(contents[1], {
        'role': 'model',
        'parts': [
          {
            'functionCall': {
              'name': 'Read',
              'args': {'file': 'x'},
              'id': 'u1',
            },
            'thoughtSignature': skipThoughtSignature,
          },
        ],
      });
      expect(contents[2]['role'], 'user');
      final response =
          ((contents[2]['parts'] as List).single as Map)['functionResponse']
              as Map;
      expect(response['name'], 'Read');
      expect(response['id'], 'u1');
      expect((response['response'] as Map)['output'], contains('interrupted'));
    });

    test('handles supported inlineData, sniffs mimeType, and omits '
        'unsupported image formats', () {
      final png = base64Encode([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
      ]);
      final gif = base64Encode('GIF89a1234'.codeUnits);
      final out = convertClaudeRequestToGemini({
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'image',
                'source': {
                  'type': 'base64',
                  'media_type': 'application/octet-stream',
                  'data': png,
                },
              },
              {
                'type': 'image',
                'source': {
                  'type': 'base64',
                  'media_type': 'image/gif',
                  'data': gif,
                },
              },
              {
                'type': 'document',
                'source': {
                  'type': 'base64',
                  'media_type': 'application/pdf',
                  'data': 'JVBERi0xLjQ=',
                },
              },
            ],
          },
        ],
      }, model: 'gemini-2.5-pro');
      final parts = ((out['contents'] as List).single as Map)['parts'] as List;
      expect(parts[0], {
        'inlineData': {'mimeType': 'image/png', 'data': png},
      });
      expect((parts[1] as Map)['text'], contains('image/gif'));
      expect(parts[2], {
        'inlineData': {'mimeType': 'application/pdf', 'data': 'JVBERi0xLjQ='},
      });
    });

    test('maps web_search tool to googleSearch with domain instructions', () {
      final out = convertClaudeRequestToGemini({
        'messages': [
          {'role': 'user', 'content': 'latest dart release'},
        ],
        'tools': [
          {
            'type': 'web_search_20250305',
            'name': 'web_search',
            'allowed_domains': ['dart.dev'],
            'blocked_domains': ['spam.example'],
          },
        ],
      }, model: 'gemini-2.5-flash');
      expect(out['tools'], [
        {'googleSearch': <String, Object?>{}},
      ]);
      final system =
          (((out['systemInstruction'] as Map)['parts'] as List).single
              as Map)['text'];
      expect(system, contains('dart.dev'));
      expect(system, contains('spam.example'));
    });

    test('configures thinkingLevel for Gemini 3+/4+ and thinkingBudget for '
        'Gemini 2.5', () {
      expect(geminiThinkingConfig('gemini-4-carbon', effort: 'xhigh'), {
        'includeThoughts': true,
        'thinkingLevel': 'xhigh',
      });
      expect(geminiThinkingConfig('gemini-4-carbon', effort: 'medium'), {
        'includeThoughts': true,
        'thinkingLevel': 'medium',
      });
      expect(geminiThinkingConfig('gemini-3-pro', effort: 'medium'), {
        'includeThoughts': true,
        'thinkingLevel': 'high',
      });
      expect(geminiThinkingConfig('gemini-3-pro', effort: 'xhigh'), {
        'includeThoughts': true,
        'thinkingLevel': 'high',
      });
      expect(geminiThinkingConfig('gemini-3-flash', effort: 'medium'), {
        'includeThoughts': true,
        'thinkingLevel': 'medium',
      });
      expect(geminiThinkingConfig('gemini-3-flash', effort: 'minimal'), {
        'includeThoughts': true,
        'thinkingLevel': 'minimal',
      });
      expect(geminiThinkingConfig('gemini-3-pro', effort: 'none'), {
        'includeThoughts': true,
        'thinkingLevel': 'low',
      });
      expect(geminiThinkingConfig('gemini-2.5-pro', effort: 'none'), {
        'thinkingBudget': 128,
      });
      expect(geminiThinkingConfig('gemini-2.5-flash', effort: 'none'), {
        'thinkingBudget': 0,
      });
      expect(geminiThinkingConfig('gemini-2.5-pro', effort: 'high'), {
        'includeThoughts': true,
        'thinkingBudget': 24576,
      });
      expect(
        geminiThinkingConfig(
          'gemini-2.5-pro',
          thinking: {'type': 'enabled', 'budget_tokens': 12000},
        ),
        {'includeThoughts': true, 'thinkingBudget': 12000},
      );
      expect(
        geminiThinkingConfig('gemini-3-pro-image', effort: 'high'),
        isNull,
      );
      expect(geminiThinkingConfig('gemini-2.5-pro'), isNull);
    });
  });

  group('AntigravityResponseTranslator.convertJson', () {
    test('decodes single JSON object and JSON array Gemini replies', () {
      final translator = AntigravityResponseTranslator(
        model: 'gemini-2.5-pro',
        errorFallback: 'Gemini failed',
      );
      translator.convertJson([
        {
          'responseId': 'r1',
          'candidates': [
            {
              'content': {
                'parts': [
                  {'thought': true, 'text': 'plan'},
                  {'text': 'Hello '},
                ],
              },
            },
          ],
        },
        {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'world!'},
                ],
              },
              'finishReason': 'STOP',
            },
          ],
          'usageMetadata': {
            'promptTokenCount': 20,
            'cachedContentTokenCount': 5,
            'candidatesTokenCount': 8,
            'thoughtsTokenCount': 4,
          },
        },
      ]);
      translator.finish();
      final message = antigravityMessage(translator.events)!;
      expect(message['id'], 'msg_r1');
      expect(message['content'], [
        {'type': 'thinking', 'thinking': 'plan'},
        {'type': 'text', 'text': 'Hello world!'},
      ]);
      expect(message['stop_reason'], 'end_turn');
      expect(message['usage'], {
        'input_tokens': 15,
        'cache_read_input_tokens': 5,
        'output_tokens': 12,
        'output_tokens_details': {'thinking_tokens': 4},
      });
    });
  });
}
