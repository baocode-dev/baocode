import 'dart:convert';

import 'package:baocode/models/antigravity/antigravity_api.dart';
import 'package:baocode/models/proxy/translate/antigravity_cloak.dart';
import 'package:baocode/models/proxy/translate/antigravity_request.dart';
import 'package:baocode/models/proxy/translate/antigravity_response.dart';
import 'package:baocode/models/proxy/translate/antigravity_schema.dart';
import 'package:baocode/models/proxy/translate/antigravity_signature.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _model(
  String name, {
  double? left,
  String? reset,
  int? context,
  bool disabled = false,
}) => {
  'displayName': name,
  'maxTokens': ?context,
  if (disabled) 'disabled': true,
  'quotaInfo': {'remainingFraction': ?left, 'resetTime': ?reset},
};

void main() {
  final listed = {
    'models': {
      'gemini-4-neon-low': _model(
        'Gemini 4 Neon (Low)',
        left: 0.8,
        context: 1048576,
      ),
      'gemini-4-neon-medium': _model(
        'Gemini 4 Neon (Medium)',
        left: 0.8,
        context: 1048576,
      ),
      'gemini-4-neon-high': _model(
        'Gemini 4 Neon (High)',
        left: 0.8,
        context: 1048576,
      ),
      'claude-opus-5-5-high': _model('Claude Opus 5.5 (High)', left: 0.5),
      'claude-opus-5-5-low': _model('Claude Opus 5.5 (Low)', left: 0.5),
      'gemini-3-flash': _model('Gemini 3 Flash', left: 1),
      'gpt-oss-120b-medium': _model('GPT-OSS 120B (Medium)'),
      'chat_20706': _model('internal'),
      'tab_flash_lite_preview': _model('tab'),
      'gemini-3.1-flash-image': _model('Gemini 3.1 Flash Image', left: 0.9),
      'gemini-4-argon-high': _model('Gemini 4 Argon', disabled: true),
    },
    'agentModelSorts': [
      {
        'groups': [
          {
            'modelIds': ['claude-opus-5-5-high', 'gemini-4-neon-high'],
          },
        ],
      },
    ],
  };

  group('models', () {
    test('hides what is not for a conversation, as the picker orders', () {
      final models = parseAntigravityModels(listed);
      final ids = models.map((m) => m.id).toList();
      expect(ids.first, 'claude-opus-5-5-high');
      expect(ids[1], 'gemini-4-neon-high');
      expect(ids, isNot(contains('chat_20706')));
      expect(ids, isNot(contains('tab_flash_lite_preview')));
      expect(ids, contains('gemini-3.1-flash-image'));
      expect(ids, isNot(contains('gemini-4-argon-high')));
      // Left out once none is left.
      expect(
        models.firstWhere((m) => m.id == 'gpt-oss-120b-medium').remaining,
        0,
      );
    });

    test('a family is one model with its levels', () {
      final remote = antigravityRemoteModels(parseAntigravityModels(listed));
      final neon = remote.firstWhere((m) => m.id == 'gemini-4-neon');
      expect(neon.label, 'Gemini 4 Neon');
      expect(neon.efforts, ['low', 'medium', 'high']);
      expect(neon.contextWindow, 1048576);
      final opus = remote.firstWhere((m) => m.id == 'claude-opus-5-5');
      expect(opus.efforts, ['low', 'high']);
      // One alone keeps its id, with the efforts its thinking takes.
      final flash = remote.firstWhere((m) => m.id == 'gemini-3-flash');
      expect(flash.efforts, ['low', 'medium', 'high']);
      final oss = remote.firstWhere((m) => m.id == 'gpt-oss-120b-medium');
      expect(oss.efforts, isEmpty);
      expect(oss.images, isFalse);
      final painter = remote.firstWhere(
        (m) => m.id == 'gemini-3.1-flash-image',
      );
      expect(painter.label, 'Gemini 3.1 Flash Image');
      expect(painter.efforts, isEmpty);
    });

    test('a family is asked at the level nearest the effort', () {
      final ids = parseAntigravityModels(listed).map((m) => m.id);
      expect(
        antigravityModelId(ids, 'gemini-4-neon', 'low'),
        'gemini-4-neon-low',
      );
      expect(
        antigravityModelId(ids, 'gemini-4-neon', 'xhigh'),
        'gemini-4-neon-high',
      );
      expect(
        antigravityModelId(ids, 'gemini-4-neon', null),
        'gemini-4-neon-high',
      );
      expect(
        antigravityModelId(ids, 'claude-opus-5-5', 'medium'),
        'claude-opus-5-5-high',
      );
      expect(
        antigravityModelId(ids, 'gemini-3-flash', 'high'),
        'gemini-3-flash',
      );
      // A variant picked by its own id before families were one.
      expect(
        antigravityModelId(ids, 'gemini-4-neon-low', 'high'),
        'gemini-4-neon-high',
      );
    });
  });

  group('quota', () {
    final now = DateTime.utc(2026, 11, 21, 12);
    final models = parseAntigravityModels(listed);

    test("each group's windows, of the models drawing on them", () {
      final usage = antigravityUsage(
        models: models,
        now: now,
        plan: 'Google AI Pro',
        summary: {
          'groups': [
            {
              'displayName': 'Gemini Models',
              'buckets': [
                {
                  'window': '5h',
                  'remainingFraction': 0.75,
                  'resetTime': '2026-11-21T15:00:00Z',
                },
                {'window': 'weekly', 'remainingFraction': 0.5},
              ],
            },
            {
              'displayName': 'Claude and GPT models',
              'buckets': [
                {'window': '5h', 'remainingFraction': 0},
                {'window': 'weekly', 'disabled': true},
              ],
            },
          ],
        },
      );
      expect(usage.plan, 'Google AI Pro');
      expect(usage.windows, hasLength(3));
      final gemini = usage.windowsFor('gemini-4-neon');
      expect(gemini.map((w) => w.name), ['Gemini', 'Gemini']);
      expect(gemini.map((w) => w.minutes), [300, 10080]);
      expect(gemini.first.usedPercent, 25);
      expect(gemini.first.resetsAt, DateTime.utc(2026, 11, 21, 15));
      final claude = usage.windowsFor('claude-opus-5-5');
      expect(claude.single.name, 'Claude & GPT');
      expect(claude.single.usedPercent, 100);
      expect(
        usage.windowsFor('gpt-oss-120b-medium').single.name,
        'Claude & GPT',
      );
    });

    test("a bucket not drawn on yet has no reset: it rolls with the clock", () {
      final usage = antigravityUsage(
        models: models,
        now: now,
        summary: {
          'groups': [
            {
              'displayName': 'Gemini Models',
              'buckets': [
                {
                  'window': '5h',
                  'remainingFraction': 1,
                  'resetTime': '2026-11-21T17:00:20Z',
                },
                {
                  'window': 'weekly',
                  'remainingFraction': 0.9,
                  'resetTime': '2026-11-28T12:00:00Z',
                },
              ],
            },
          ],
        },
      );
      final gemini = usage.windowsFor('gemini-4-neon');
      expect(gemini.first.resetsAt, isNull);
      expect(gemini.last.resetsAt, DateTime.utc(2026, 11, 28, 12));
    });

    test('loose buckets, by the family their ids tell', () {
      final usage = antigravityUsage(
        models: models,
        now: now,
        summary: {
          'buckets': [
            {'bucketId': 'gemini-5h', 'window': '5h', 'remainingFraction': 0.5},
            {
              'bucketId': '3p-weekly',
              'window': 'weekly',
              'remainingFraction': 0,
            },
          ],
        },
      );
      expect(usage.windowsFor('gemini-4-neon').single.usedPercent, 50);
      final claude = usage.windowsFor('claude-opus-5-5').single;
      expect(claude.name, 'Claude & GPT');
      expect(claude.minutes, 10080);
    });

    test("both hosts' summaries as one, the more used bucket of each", () {
      final merged = mergeAntigravitySummaries([
        {
          'groups': [
            {
              'displayName': 'Gemini Models',
              'buckets': [
                {'bucketId': 'g-5h', 'window': '5h', 'remainingFraction': 1},
              ],
            },
          ],
        },
        null,
        {
          'groups': [
            {
              'displayName': 'Gemini Models',
              'buckets': [
                {'bucketId': 'g-5h', 'window': '5h', 'remainingFraction': 0.4},
              ],
            },
            {
              'displayName': 'Claude and GPT models',
              'buckets': [
                {'bucketId': 'c-5h', 'window': '5h', 'remainingFraction': 0.8},
              ],
            },
          ],
        },
      ]);
      final usage = antigravityUsage(models: models, now: now, summary: merged);
      expect(usage.windows, hasLength(2));
      expect(
        usage.windowsFor('gemini-4-neon').single.usedPercent,
        closeTo(60, 1e-9),
      );
      expect(
        usage.windowsFor('claude-opus-5-5').single.usedPercent,
        closeTo(20, 1e-9),
      );
    });

    test("without groups, each family's own five hours", () {
      final usage = antigravityUsage(models: models, now: now);
      expect(usage.windowsFor('claude-opus-5-5').single.usedPercent, 50);
      expect(
        usage.windowsFor('gemini-4-neon').single.usedPercent,
        closeTo(20, 1e-9),
      );
    });

    test('a quota used up is told from a moment of rate limit', () {
      expect(
        antigravityLimitReset(
          429,
          '{"error":{"message":"You have exhausted your capacity on this model. '
          'Your quota will reset after 1h43m56s."}}',
          now,
        ),
        now.add(const Duration(hours: 1, minutes: 43, seconds: 56)),
      );
      expect(
        antigravityLimitReset(
          429,
          jsonEncode({
            'error': {
              'status': 'RESOURCE_EXHAUSTED',
              'details': [
                {'reason': 'QUOTA_EXHAUSTED'},
                {'retryDelay': '3600s'},
              ],
            },
          }),
          now,
        ),
        now.add(const Duration(hours: 1)),
      );
      const moment =
          '{"error":{"details":[{"reason":"RATE_LIMIT_EXCEEDED"},'
          '{"retryDelay":"0.5s"}]}}';
      expect(antigravityLimitReset(429, moment, now), isNull);
      expect(antigravityRetryAfter(moment), const Duration(milliseconds: 500));
      expect(antigravityLimitReset(400, moment, now), isNull);
    });
  });

  test('a session is the same over a conversation', () {
    final a = antigravitySessionId('session\nhello');
    expect(a, startsWith('-'));
    expect(a, antigravitySessionId('session\nhello'));
    expect(a, isNot(antigravitySessionId('session\nbye')));
    expect(BigInt.parse(a.substring(1)) < BigInt.one << 63, isTrue);
  });

  test('the version comes from the feed', () {
    expect(parseAntigravityVersion("version: 2.10.3\nfiles:\n"), '2.10.3');
    expect(parseAntigravityVersion("version: '2.9.1'"), '2.9.1');
    expect(parseAntigravityVersion('nothing'), isNull);
  });

  group('cloak', () {
    test("Claude Code's billing line goes, the rest as written", () {
      expect(
        antigravityCloak(
          'x-anthropic-billing-header: cc_version=2.1; cch=00000;\n'
          'You are Claude Code.',
        ),
        'You are Claude Code.',
      );
    });

    test('lines turned away are reworded, however spaced or broken up', () {
      expect(
        antigravityCloak(
          "You are a Claude agent, built on Anthropic's Claude Agent SDK.",
        ),
        'You are a Claude agent, built on the Claude Agent SDK by Anthropic.',
      );
      expect(
        antigravityCloak('You  are\nOpenCode, the best'),
        "You're\nOpenCode, the best",
      );
      expect(
        antigravityCloak('You are Co​dex, an agent based on GPT-5.'),
        'You are Codex, an agent built on GPT-5.',
      );
      expect(antigravityCloak('Nothing here.'), 'Nothing here.');
      // In a user's turn, Codex's lines alone.
      expect(
        antigravityCloakUserText(
          'You are OpenCode. You are Codex, an agent based on GPT-5.',
        ),
        'You are OpenCode. You are Codex, an agent built on GPT-5.',
      );
    });
  });

  group('signatures', () {
    test('ride in the id and come back off it', () {
      final store = MemorySignatureStore();
      final id = signedToolId('call_1', 'c2lnbmF0dXJl', store);
      expect(id, matches(RegExp(r'^call_1__tsk16__[A-Za-z0-9_-]{16}$')));
      expect(unsignedToolId(id, store), ('call_1', 'c2lnbmF0dXJl'));
      expect(signedToolId('call_1', null, store), 'call_1');
      expect(unsignedToolId('toolu_123', store), ('toolu_123', null));
    });

    test('a signature cut short or forgotten is none', () {
      final store = MemorySignatureStore();
      final id = signedToolId('call_1', 'abc', store);
      expect(unsignedToolId(id.substring(0, id.length - 2), store).$2, isNull);
      expect(unsignedToolId(id, MemorySignatureStore()).$2, isNull);
      final inline = signedToolId('call_2', 'abc', null);
      expect(unsignedToolId(inline, null), ('call_2', 'abc'));
    });
  });

  group('schema', () {
    test('cut to the subset Antigravity takes', () {
      final schema = antigravitySchema({
        r'$schema': 'http://json-schema.org/draft-07/schema#',
        'type': 'object',
        'additionalProperties': false,
        'properties': {
          'path': {'type': 'string', 'format': 'uri', 'title': 'Path'},
          'mode': {
            'anyOf': [
              {
                'type': 'string',
                'enum': ['a', '', 'b'],
              },
              {'type': 'null'},
            ],
          },
          'tags': {
            'type': ['array', 'null'],
            'items': {r'$ref': '#/definitions/tag'},
          },
          'limit': {'type': 'integer', 'exclusiveMinimum': 0},
          'never': false,
        },
        'required': ['path', 'never'],
        'definitions': {
          'tag': {'type': 'string', 'const': 'x'},
        },
      });
      expect(schema, {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
          'mode': {
            'type': 'string',
            'enum': ['a', 'b'],
            'nullable': true,
          },
          'tags': {
            'type': 'array',
            'nullable': true,
            'items': {
              'type': 'string',
              'enum': ['x'],
            },
          },
          'limit': {'type': 'integer', 'minimum': 0},
        },
        'required': ['path'],
      });
    });

    test('a reference to itself stops at its type', () {
      final schema = antigravitySchema({
        'type': 'object',
        'properties': {
          'node': {r'$ref': '#'},
        },
      });
      expect(schema['properties'], {
        'node': {'type': 'object'},
      });
    });
  });

  group('request', () {
    final store = MemorySignatureStore();
    final signedId = signedToolId('call_a', 'U0lH', store);
    Map<String, Object?> body() => {
      'model': 'gemini-4-neon',
      'max_tokens': 32000,
      'system': [
        {'type': 'text', 'text': 'x-anthropic-billing-header: cc=1;'},
        {'type': 'text', 'text': 'You are a helpful agent.'},
      ],
      'messages': [
        {'role': 'user', 'content': 'List files'},
        {
          'role': 'assistant',
          'content': [
            {'type': 'thinking', 'thinking': 'hm', 'signature': 'xyz'},
            {'type': 'text', 'text': 'Looking.'},
            {
              'type': 'tool_use',
              'id': signedId,
              'name': 'Bash',
              'input': {'command': 'ls'},
            },
            {
              'type': 'tool_use',
              'id': 'call_b',
              'name': 'Read',
              'input': {'file_path': 'a'},
            },
          ],
        },
        {
          'role': 'user',
          'content': [
            {'type': 'tool_result', 'tool_use_id': signedId, 'content': 'a\nb'},
            {'type': 'text', 'text': 'and then?'},
          ],
        },
      ],
      'tools': [
        {
          'name': 'Bash',
          'description': 'Runs a command',
          'input_schema': {
            'type': 'object',
            'properties': {
              'command': {'type': 'string'},
            },
            'required': ['command'],
          },
        },
        {'type': 'web_search_20250305', 'name': 'web_search'},
      ],
    };

    test("Gemini's turns, its signatures back on its calls", () {
      final request = convertClaudeRequestToAntigravity(
        body(),
        model: 'gemini-4-neon-high',
        effort: 'high',
        store: store,
      );
      expect(request['systemInstruction'], {
        'role': 'user',
        'parts': [
          {'text': 'You are a helpful agent.'},
        ],
      });
      final contents = request['contents'] as List;
      expect(contents.map((c) => (c as Map)['role']), [
        'user',
        'model',
        'user',
        'user',
      ]);
      final model = (contents[1] as Map)['parts'] as List;
      expect(model[0], {'text': 'Looking.'});
      expect(model[1], {
        'functionCall': {
          'name': 'Bash',
          'args': {'command': 'ls'},
          'id': 'call_a',
        },
        'thoughtSignature': 'U0lH',
      });
      // The step is signed: its later call goes without.
      expect((model[2] as Map).containsKey('thoughtSignature'), isFalse);
      // The call answered nowhere is answered as interrupted, beside the
      // result; what the user said follows in a turn of its own.
      final results = (contents[2] as Map)['parts'] as List;
      expect(results, [
        {
          'functionResponse': {
            'name': 'Read',
            'id': 'call_b',
            'response': {
              'result': '[The result of this tool call is unavailable: the turn was interrupted.]',
            },
          },
        },
        {
          'functionResponse': {
            'name': 'Bash',
            'id': 'call_a',
            'response': {'result': 'a\nb'},
          },
        },
      ]);
      expect((contents[3] as Map)['parts'], [
        {'text': 'and then?'},
      ]);
      expect(request['tools'], [
        {
          'functionDeclarations': [
            {
              'name': 'Bash',
              'description': 'Runs a command',
              'parameters': {
                'type': 'object',
                'properties': {
                  'command': {'type': 'string'},
                },
                'required': ['command'],
              },
            },
          ],
        },
      ]);
      expect(request['toolConfig'], {
        'functionCallingConfig': {'mode': 'AUTO'},
      });
      // Gemini's output is not capped; it thinks at its variant's level.
      expect(request['generationConfig'], {
        'thinkingConfig': {'includeThoughts': true, 'thinkingLevel': 'high'},
      });
    });

    test("Claude's: one result turn, calls validated, output capped", () {
      final request = convertClaudeRequestToAntigravity(
        body(),
        model: 'claude-opus-5-5-high',
        store: store,
      );
      final contents = request['contents'] as List;
      expect(contents.map((c) => (c as Map)['role']), [
        'user',
        'model',
        'user',
      ]);
      final model = (contents[1] as Map)['parts'] as List;
      expect(
        model
            .whereType<Map>()
            .where((p) => p.containsKey('functionCall'))
            .map((p) => p['thoughtSignature']),
        [skipThoughtSignature, skipThoughtSignature],
      );
      final last = (contents[2] as Map)['parts'] as List;
      expect(last.last, {'text': 'and then?'});
      expect(request['toolConfig'], {
        'functionCallingConfig': {'mode': 'VALIDATED'},
      });
      expect(request['generationConfig'], {'maxOutputTokens': 32000});
    });

    test('a history ending with the model gets a turn after it', () {
      final request = convertClaudeRequestToAntigravity({
        'messages': [
          {'role': 'assistant', 'content': 'Hi'},
        ],
      }, model: 'gemini-3-flash');
      expect((request['contents'] as List).map((c) => (c as Map)['role']), [
        'user',
        'model',
        'user',
      ]);
    });

    test('the first user text seeds the session', () {
      expect(antigravityFirstUserText(body()), 'List files');
    });

    test(
      'web_search translates to googleSearch on Gemini without functions',
      () {
        final searchBody = {
          'system': [
            {'type': 'text', 'text': 'Search the web.'},
          ],
          'messages': [
            {'role': 'user', 'content': 'Search for: Dart 4'},
          ],
          'tools': [
            {
              'type': 'web_search_20250305',
              'name': 'web_search',
              'allowed_domains': ['dart.dev', 'pub.dev'],
            },
          ],
        };
        expect(antigravitySupportsWebSearch('gemini-4-neon-high'), isTrue);
        expect(antigravitySupportsWebSearch('claude-opus-5-5-high'), isFalse);
        expect(antigravitySupportsWebSearch('gpt-oss-120b-medium'), isFalse);
        expect(antigravitySupportsWebSearch('gemini-3.1-flash-image'), isFalse);

        final request = convertClaudeRequestToAntigravity(
          searchBody,
          model: 'gemini-4-neon-high',
        );
        expect(request['tools'], [
          {'googleSearch': <String, Object?>{}},
        ]);
        expect(request.containsKey('toolConfig'), isFalse);
        expect(request['systemInstruction'], {
          'role': 'user',
          'parts': [
            {
              'text':
                  'Search the web.\n\n'
                  'Restrict web search results to these domains: dart.dev, pub.dev.',
            },
          ],
        });

        // Not sent for unsupported models or when tool_choice is none.
        final claudeReq = convertClaudeRequestToAntigravity(
          searchBody,
          model: 'claude-opus-5-5-high',
        );
        expect(claudeReq.containsKey('tools'), isFalse);
        final noneReq = convertClaudeRequestToAntigravity({
          ...searchBody,
          'tool_choice': {'type': 'none'},
        }, model: 'gemini-4-neon-high');
        expect(noneReq.containsKey('tools'), isFalse);
      },
    );
  });

  group('thinking', () {
    test(
      'a level for Gemini 3 on, a budget before, none where it does not',
      () {
        expect(antigravityThinking('gemini-3-flash'), isNull);
        expect(antigravityThinking('gemini-3-flash', effort: 'medium'), {
          'includeThoughts': true,
          'thinkingLevel': 'medium',
        });
        expect(antigravityThinking('gemini-4-neon-xhigh'), {
          'includeThoughts': true,
          'thinkingLevel': 'xhigh',
        });
        expect(antigravityThinking('gemini-2.5-flash', effort: 'none'), {
          'thinkingBudget': 0,
        });
        expect(
          antigravityThinking('claude-opus-5-5-high', effort: 'high'),
          isNull,
        );
        expect(
          antigravityThinking('gpt-oss-120b-medium', effort: 'high'),
          isNull,
        );
        expect(
          antigravityThinking(
            'claude-sonnet-4-5-thinking',
            effort: 'high',
            maxTokens: 8000,
          ),
          {'includeThoughts': true, 'thinkingBudget': 7999},
        );
      },
    );
  });

  group('response', () {
    String line(Object chunk) => 'data: ${jsonEncode({'response': chunk})}';

    List<Map<String, Object?>> decode(String frames) => [
      for (final l in const LineSplitter().convert(frames))
        if (l.startsWith('data: '))
          jsonDecode(l.substring(6)) as Map<String, Object?>,
    ];

    test("thinking, text and a call, as Anthropic's events", () {
      final store = MemorySignatureStore();
      final translator = AntigravityResponseTranslator(
        model: 'gemini-4-neon(high)',
        store: store,
      );
      final out = StringBuffer()
        ..write(
          translator.convert(
            line({
              'responseId': 'r1',
              'usageMetadata': {
                'promptTokenCount': 1000,
                'cachedContentTokenCount': 800,
              },
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'thought': true, 'text': 'Let me see'},
                    ],
                  },
                },
              ],
            }),
          ),
        )
        ..write(
          translator.convert(
            line({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'Listing.'},
                      {
                        'functionCall': {
                          'name': 'default_api:Bash',
                          'args': {'command': 'ls'},
                        },
                        'thoughtSignature': 'U0lH',
                      },
                    ],
                  },
                  'finishReason': 'STOP',
                },
              ],
              'usageMetadata': {
                'promptTokenCount': 1000,
                'cachedContentTokenCount': 800,
                'candidatesTokenCount': 20,
                'thoughtsTokenCount': 30,
              },
            }),
          ),
        )
        ..write(translator.finish());
      final events = decode(out.toString());
      expect(events.map((e) => e['type']), [
        'message_start',
        'content_block_start',
        'content_block_delta',
        'content_block_stop',
        'content_block_start',
        'content_block_delta',
        'content_block_stop',
        'content_block_start',
        'content_block_delta',
        'content_block_stop',
        'message_delta',
        'message_stop',
      ]);
      expect((events[0]['message'] as Map)['usage'], {
        'input_tokens': 200,
        'cache_read_input_tokens': 800,
        'output_tokens': 0,
      });
      final call = events[7]['content_block'] as Map;
      expect(call['name'], 'Bash');
      expect(unsignedToolId(call['id'] as String, store).$2, 'U0lH');
      expect(events[8]['delta'], {
        'type': 'input_json_delta',
        'partial_json': '{"command":"ls"}',
      });
      expect(events[10]['delta'], {
        'stop_reason': 'tool_use',
        'stop_sequence': null,
      });
      expect(events[10]['usage'], {
        'input_tokens': 200,
        'cache_read_input_tokens': 800,
        'output_tokens': 50,
        'output_tokens_details': {'thinking_tokens': 30},
      });
      final message = antigravityMessage(translator.events)!;
      expect(message['stop_reason'], 'tool_use');
      expect((message['content'] as List).map((b) => (b as Map)['type']), [
        'thinking',
        'text',
        'tool_use',
      ]);
      expect(((message['content'] as List)[2] as Map)['input'], {
        'command': 'ls',
      });
    });

    test('a call written out as text is the call it meant', () {
      final translator = AntigravityResponseTranslator(model: 'm');
      final out = StringBuffer()
        ..write(
          translator.convert(
            line({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'Look.call:default_api:Ba'},
                    ],
                  },
                },
              ],
            }),
          ),
        )
        ..write(
          translator.convert(
            line({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'sh{command:<ctrl46>ls -la<ctrl46>}'},
                    ],
                  },
                  'finishReason': 'STOP',
                },
              ],
            }),
          ),
        )
        ..write(translator.finish());
      final message = antigravityMessage(translator.events)!;
      final content = message['content'] as List;
      expect((content[0] as Map)['text'], 'Look.');
      expect((content[1] as Map)['name'], 'Bash');
      expect((content[1] as Map)['input'], {'command': 'ls -la'});
      expect(message['stop_reason'], 'tool_use');
      expect(out.toString(), contains('message_stop'));
    });

    test('an error ends the stream as one', () {
      final translator = AntigravityResponseTranslator(model: 'm');
      final frames = translator.convert(
        'data: {"error":{"message":"Resource has been exhausted"}}',
      );
      expect(frames, contains('event: error'));
      expect(translator.finish(), isEmpty);
    });

    test(
      'groundingMetadata emits server_tool_use and web_search_tool_result',
      () {
        final translator = AntigravityResponseTranslator(
          model: 'gemini-4-neon(high)',
        );
        final out = StringBuffer()
          ..write(
            translator.convert(
              line({
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'Gemini 4 Neon is out.'},
                      ],
                    },
                    'groundingMetadata': {
                      'webSearchQueries': ['Gemini 4 Neon'],
                    },
                  },
                ],
              }),
            ),
          )
          ..write(
            translator.convert(
              line({
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': ''},
                      ],
                    },
                    'finishReason': 'STOP',
                    'groundingMetadata': {
                      'webSearchQueries': ['Gemini 4 Neon', 'Gemini 4 pricing'],
                      'groundingChunks': [
                        {
                          'web': {
                            'uri': 'https://aistudio.google.com/docs/models',
                            'title': 'AI Studio Models',
                          },
                        },
                        {
                          'web': {
                            'uri': 'https://aistudio.google.com/docs/models',
                            'title': 'Duplicate',
                          },
                        },
                        {
                          'web': {
                            'uri': 'https://aistudio.google.com/docs/pricing',
                          },
                        },
                      ],
                    },
                  },
                ],
                'usageMetadata': {
                  'promptTokenCount': 50,
                  'candidatesTokenCount': 12,
                },
              }),
            ),
          )
          ..write(translator.finish());
        final events = decode(out.toString());
        final message = antigravityMessage(translator.events)!;
        expect(message['stop_reason'], 'end_turn');
        expect(message['usage'], {
          'input_tokens': 50,
          'output_tokens': 12,
          'server_tool_use': {'web_search_requests': 1},
        });
        final content = message['content'] as List;
        expect(content.map((b) => (b as Map)['type']), [
          'text',
          'server_tool_use',
          'web_search_tool_result',
        ]);
        final use = content[1] as Map;
        expect(use['name'], 'web_search');
        expect(use['input'], {'query': 'Gemini 4 Neon; Gemini 4 pricing'});
        final result = content[2] as Map;
        expect(result['tool_use_id'], use['id']);
        expect(result['content'], [
          {
            'type': 'web_search_result',
            'title': 'AI Studio Models',
            'url': 'https://aistudio.google.com/docs/models',
            'page_age': null,
          },
          {
            'type': 'web_search_result',
            'title': 'https://aistudio.google.com/docs/pricing',
            'url': 'https://aistudio.google.com/docs/pricing',
            'page_age': null,
          },
        ]);
        expect(events.where((e) => e['type'] == 'message_stop'), hasLength(1));
      },
    );
  });
}
