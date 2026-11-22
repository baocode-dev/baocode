import 'dart:convert';
import 'dart:io';

import 'package:bao_websearch/bao_websearch.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> claudeCodeSearch({Object? tools, Object? choice}) => {
  'model': 'some-model',
  'messages': [
    {
      'role': 'user',
      'content': [
        {'type': 'text', 'text': 'Perform a web search for the query: dart 4'},
      ],
    },
  ],
  'tools':
      tools ??
      [
        {
          'type': 'web_search_20250305',
          'name': 'web_search',
          'max_uses': 8,
          'blocked_domains': ['spam.test'],
        },
      ],
  'tool_choice': ?choice,
};

void main() {
  test('a web search tool\'s own request', () {
    final body = claudeCodeSearch();
    expect(onlyWebSearchTool(body)?['name'], 'web_search');
    expect(webSearchQueryOf(body), 'dart 4');
    expect(toolDomains(onlyWebSearchTool(body), 'blocked_domains'), [
      'spam.test',
    ]);
    expect(toolDomains(onlyWebSearchTool(body), 'allowed_domains'), isEmpty);
    expect(
      webSearchQueryOf({
        'messages': [
          {'role': 'user', 'content': 'Search for: flutter 4'},
        ],
      }),
      'flutter 4',
    );
    // Beside tools of its own, or with tools forbidden: not one.
    expect(
      onlyWebSearchTool(
        claudeCodeSearch(
          tools: [
            {'type': 'web_search_20260209', 'name': 'web_search'},
            {'name': 'Bash', 'input_schema': <String, Object?>{}},
          ],
        ),
      ),
      isNull,
    );
    expect(
      onlyWebSearchTool(claudeCodeSearch(choice: {'type': 'none'})),
      isNull,
    );
    expect(onlyWebSearchTool(claudeCodeSearch(tools: [])), isNull);
  });

  test('a search made here, as the API\'s own would answer', () {
    final message = localSearchMessage(
      model: 'm',
      query: 'dart 4',
      hits: [
        SearchHit('Dart', 'https://dart.dev', 'The language', ['bing']),
      ],
    );
    final content = message['content'] as List;
    expect(
      [for (final block in content) (block as Map)['type']],
      ['server_tool_use', 'web_search_tool_result', 'text'],
    );
    expect(
      (content[2] as Map)['text'],
      '1. Dart\nURL: https://dart.dev\nThe language',
    );
    expect(nativeSearchOutcome(jsonEncode(message)), NativeSearch.searched);

    // Streamed, the same message.
    final frames = sseFrames(messageEvents(message));
    expect(frames, startsWith('event: message_start\ndata: '));
    expect(nativeSearchOutcome(frames), NativeSearch.searched);
    final deltas = [
      for (final line in LineSplitter.split(frames))
        if (line.startsWith('data: ')) jsonDecode(line.substring(6)) as Map,
    ].where((event) => event['type'] == 'content_block_delta').toList();
    expect((deltas[0]['delta'] as Map)['partial_json'], '{"query":"dart 4"}');
    expect((deltas[1]['delta'] as Map)['text'], contains('https://dart.dev'));
    // Nothing paid for.
    expect(frames, isNot(contains('web_search_requests')));

    final failed = localSearchMessage(model: 'm', query: 'q', error: 'down');
    expect(((failed['content'] as List)[1] as Map)['content'], {
      'type': 'web_search_tool_result_error',
      'error_code': 'unavailable',
      'message': 'down',
    });
  });

  group('what an answer says of the API\'s own search', () {
    String sse(List<Map<String, Object?>> events) => [
      for (final event in events)
        'event: ${event['type']}\ndata: ${jsonEncode(event)}\n',
    ].join('\n');

    test('it searched', () {
      expect(
        nativeSearchOutcome(
          sse([
            {'type': 'message_start', 'message': <String, Object?>{}},
            {
              'type': 'content_block_start',
              'index': 0,
              'content_block': {'type': 'server_tool_use', 'id': 's'},
            },
            {
              'type': 'content_block_start',
              'index': 1,
              'content_block': {
                'type': 'web_search_tool_result',
                'content': <Object?>[],
              },
            },
          ]),
        ),
        NativeSearch.searched,
      );
    });

    test('it answered without searching: not supported', () {
      expect(
        nativeSearchOutcome(
          sse([
            {'type': 'message_start', 'message': <String, Object?>{}},
            {
              'type': 'content_block_start',
              'index': 0,
              'content_block': {'type': 'text', 'text': ''},
            },
            {'type': 'message_stop'},
          ]),
        ),
        NativeSearch.unsupported,
      );
      expect(
        nativeSearchOutcome(
          jsonEncode({
            'type': 'message',
            'content': [
              {'type': 'tool_use', 'name': 'web_search', 'input': {}},
            ],
          }),
        ),
        NativeSearch.unsupported,
      );
    });

    test('a search that failed says nothing', () {
      expect(
        nativeSearchOutcome(
          sse([
            {'type': 'message_start', 'message': <String, Object?>{}},
            {
              'type': 'content_block_start',
              'index': 0,
              'content_block': {'type': 'server_tool_use', 'id': 's'},
            },
            {
              'type': 'content_block_start',
              'index': 1,
              'content_block': {
                'type': 'web_search_tool_result',
                'content': {'error_code': 'too_many_requests'},
              },
            },
          ]),
        ),
        NativeSearch.failed,
      );
      // Cut off after asking.
      expect(
        nativeSearchOutcome(
          sse([
            {'type': 'message_start', 'message': <String, Object?>{}},
            {
              'type': 'content_block_start',
              'index': 0,
              'content_block': {'type': 'server_tool_use', 'id': 's'},
            },
          ]),
        ),
        NativeSearch.failed,
      );
      expect(
        nativeSearchOutcome(
          sse([
            {'type': 'message_start', 'message': <String, Object?>{}},
            {
              'type': 'error',
              'error': {'type': 'overloaded_error'},
            },
          ]),
        ),
        NativeSearch.failed,
      );
      expect(nativeSearchOutcome(''), NativeSearch.failed);
      expect(nativeSearchOutcome('<html>'), NativeSearch.failed);
    });

    test('search said to be unavailable: not supported', () {
      expect(
        nativeSearchOutcome(
          jsonEncode(localSearchMessage(model: 'm', query: 'q', error: 'no')),
        ),
        NativeSearch.unsupported,
      );
    });
  });

  test('a refusal of the tool itself', () {
    expect(
      refusesWebSearchTool(
        400,
        '{"error":{"message":"tools.0: unknown tool type web_search_20250305"}}',
      ),
      isTrue,
    );
    expect(refusesWebSearchTool(422, 'Unsupported tool'), isTrue);
    expect(refusesWebSearchTool(400, 'max_tokens too large'), isFalse);
    expect(refusesWebSearchTool(429, 'tool rate limit'), isFalse);
    expect(refusesWebSearchTool(500, 'web_search failed'), isFalse);
    expect(refusesWebSearchTool(401, 'invalid key'), isFalse);
  });

  group('native support', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('websearch'));
    tearDown(() => temp.deleteSync(recursive: true));

    test('kept 5 hours, in a file', () async {
      var now = DateTime(2026, 11, 22, 10);
      final path = '${temp.path}/cache/support.json';
      final support = NativeSearchSupport(path: () => path, now: () => now);
      expect(support.lookup('p', 'anthropic', 'm'), isNull);
      support
        ..record('p', 'anthropic', 'm', false)
        ..record('p', 'openaiResponses', 'm', true);
      expect(support.lookup('p', 'anthropic', 'm'), isFalse);
      expect(support.lookup('p', 'openaiResponses', 'm'), isTrue);
      expect(support.lookup('p', 'anthropic', 'other'), isNull);
      await support.flush();

      // Read back by another.
      final again = NativeSearchSupport(path: () => path, now: () => now);
      expect(again.lookup('p', 'anthropic', 'm'), isFalse);
      expect(again.lookup('p', 'openaiResponses', 'm'), isTrue);

      now = now.add(const Duration(hours: 4, minutes: 59));
      expect(again.lookup('p', 'anthropic', 'm'), isFalse);
      now = now.add(const Duration(minutes: 1));
      expect(again.lookup('p', 'anthropic', 'm'), isNull);
    });

    test('an unreadable file is found out again', () {
      final path = '${temp.path}/support.json';
      File(path).writeAsStringSync('{not json');
      final support = NativeSearchSupport(path: () => path);
      expect(support.lookup('p', 'anthropic', 'm'), isNull);
      support.record('p', 'anthropic', 'm', true);
      expect(support.lookup('p', 'anthropic', 'm'), isTrue);
    });
  });
}
