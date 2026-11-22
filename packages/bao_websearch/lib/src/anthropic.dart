import 'dart:convert';
import 'dart:math';

import 'engine.dart';

/// Whether [type] is one of Anthropic's server-side web search tools
/// (`web_search_20250305`, `web_search_20260209`, …).
bool isWebSearchToolType(String type) => type.startsWith('web_search_');

/// The `web_search` tool [body] (a Messages request) asks for, when it is
/// all it asks for: no tool of its own beside it, tools not forbidden.
/// That is a web search tool's own request (Claude Code's `WebSearch`).
Map<String, Object?>? onlyWebSearchTool(Map<String, Object?> body) {
  if (body['tool_choice'] case {'type': 'none'}) return null;
  final tools = body['tools'];
  if (tools is! List || tools.isEmpty) return null;
  Map<String, Object?>? search;
  for (final tool in tools) {
    if (tool is! Map) continue;
    if (isWebSearchToolType('${tool['type'] ?? ''}')) {
      search ??= tool.cast<String, Object?>();
    } else {
      return null;
    }
  }
  return search;
}

/// How a web search tool's request words the query, before it.
const _queryPrefixes = ['Perform a web search for the query:', 'Search for:'];

/// The query of a web search tool's request: its last user text, without
/// the words before the query.
String webSearchQueryOf(Map<String, Object?> body) {
  final messages = body['messages'];
  if (messages is! List) return '';
  for (final message in messages.reversed) {
    if (message is! Map || message['role'] != 'user') continue;
    final content = message['content'];
    final text = switch (content) {
      String() => content,
      List() => [
        for (final block in content)
          if (block is Map && block['type'] == 'text') '${block['text'] ?? ''}',
      ].join('\n'),
      _ => '',
    }.trim();
    if (text.isEmpty) continue;
    for (final prefix in _queryPrefixes) {
      if (text.startsWith(prefix)) return text.substring(prefix.length).trim();
    }
    return text;
  }
  return '';
}

/// The domains [tool] keeps to or leaves out.
List<String> toolDomains(Map<String, Object?>? tool, String name) => [
  if (tool?[name] case final List domains)
    for (final domain in domains)
      if ('$domain'.trim() case final d when d.isNotEmpty) d,
];

/// [hits] as the model reads them: each one's title, link and snippet.
String searchResultsText(List<SearchHit> hits) => [
  for (final (i, hit) in hits.indexed)
    '${i + 1}. ${hit.title}\nURL: ${hit.url}'
        '${hit.chunk.isEmpty ? '' : '\n${hit.chunk}'}',
].join('\n\n');

final _random = Random();

String _id(String prefix) {
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  return prefix +
      String.fromCharCodes([
        for (var i = 0; i < 24; i++)
          chars.codeUnitAt(_random.nextInt(chars.length)),
      ]);
}

/// The answer to a web search tool's request made here, as the API's own
/// search would give it: the search ([query]), its [hits] as
/// `web_search_result`s, then their titles, links and snippets as text;
/// or, with an [error], a `web_search_tool_result_error` saying it.
///
/// No `server_tool_use` usage: nothing was paid for.
Map<String, Object?> localSearchMessage({
  required String model,
  required String query,
  List<SearchHit> hits = const [],
  String? error,
}) {
  final toolUseId = _id('srvtoolu_');
  return {
    'id': _id('msg_'),
    'type': 'message',
    'role': 'assistant',
    'model': model,
    'content': [
      {
        'type': 'server_tool_use',
        'id': toolUseId,
        'name': 'web_search',
        'input': {'query': query},
      },
      {
        'type': 'web_search_tool_result',
        'tool_use_id': toolUseId,
        'content': error != null
            ? {
                'type': 'web_search_tool_result_error',
                'error_code': 'unavailable',
                'message': error,
              }
            : [
                for (final hit in hits)
                  {
                    'type': 'web_search_result',
                    'title': hit.title,
                    'url': hit.url,
                    'encrypted_content': '',
                    'page_age': null,
                  },
              ],
      },
      if (error == null && hits.isNotEmpty)
        {'type': 'text', 'text': searchResultsText(hits)},
    ],
    'stop_reason': 'end_turn',
    'stop_sequence': null,
    'usage': {'input_tokens': 0, 'output_tokens': 0},
  };
}

/// [message] as the events of its stream.
List<Map<String, Object?>> messageEvents(Map<String, Object?> message) {
  final content = message['content'] as List;
  return [
    {
      'type': 'message_start',
      'message': {
        ...message,
        'content': const <Object?>[],
        'stop_reason': null,
      },
    },
    for (final (index, block as Map<String, Object?>) in content.indexed) ...[
      switch (block['type']) {
        'server_tool_use' || 'tool_use' => {
          'type': 'content_block_start',
          'index': index,
          'content_block': {...block, 'input': const <String, Object?>{}},
        },
        'text' => {
          'type': 'content_block_start',
          'index': index,
          'content_block': {'type': 'text', 'text': ''},
        },
        _ => {
          'type': 'content_block_start',
          'index': index,
          'content_block': block,
        },
      },
      if (block['type'] case 'server_tool_use' || 'tool_use')
        {
          'type': 'content_block_delta',
          'index': index,
          'delta': {
            'type': 'input_json_delta',
            'partial_json': jsonEncode(block['input']),
          },
        },
      if (block['type'] == 'text')
        {
          'type': 'content_block_delta',
          'index': index,
          'delta': {'type': 'text_delta', 'text': block['text']},
        },
      {'type': 'content_block_stop', 'index': index},
    ],
    {
      'type': 'message_delta',
      'delta': {
        'stop_reason': message['stop_reason'],
        'stop_sequence': message['stop_sequence'],
      },
      'usage': message['usage'],
    },
    {'type': 'message_stop'},
  ];
}

/// [events] as server-sent events.
String sseFrames(List<Map<String, Object?>> events) => [
  for (final event in events)
    'event: ${event['type']}\ndata: ${jsonEncode(event)}\n\n',
].join();

/// What an answer to a web search tool's request says of the API's own
/// search.
enum NativeSearch {
  /// It searched: it runs the tool.
  searched,

  /// It does not run the tool: it answered without searching, or said
  /// search is not available.
  unsupported,

  /// It could not search this time (a limit, an error): says nothing
  /// either way.
  failed,
}

/// What [answer] (a Messages API answer to a web search tool's request,
/// streamed or not) says of its API's own search.
NativeSearch nativeSearchOutcome(String answer) {
  final blocks = <Map<Object?, Object?>>[];
  var answered = false;
  var failed = false;
  void message(Object? json) {
    if (json is! Map) return;
    switch (json['type']) {
      case 'message':
        answered = true;
        for (final block
            in json['content'] is List ? json['content'] as List : const []) {
          if (block is Map) blocks.add(block);
        }
      case 'message_start':
        answered = true;
      case 'content_block_start':
        if (json['content_block'] case final Map block) blocks.add(block);
      case 'error':
        failed = true;
    }
  }

  final trimmed = answer.trimLeft();
  if (trimmed.startsWith('{')) {
    try {
      message(jsonDecode(trimmed));
    } on FormatException {
      return NativeSearch.failed;
    }
  } else {
    for (final line in const LineSplitter().convert(answer)) {
      if (!line.startsWith('data:')) continue;
      try {
        message(jsonDecode(line.substring(5).trim()));
      } on FormatException {
        // Not JSON: not an event of ours.
      }
    }
  }
  var asked = false;
  for (final block in blocks) {
    switch (block['type']) {
      case 'server_tool_use':
        asked = true;
      case 'web_search_tool_result':
        final content = block['content'];
        if (content is List) return NativeSearch.searched;
        if (content case {'error_code': 'unavailable'}) {
          return NativeSearch.unsupported;
        }
        return NativeSearch.failed;
    }
  }
  if (failed || !answered || asked) return NativeSearch.failed;
  return NativeSearch.unsupported;
}

/// Whether an API's refusal ([status], [body]) of a web search tool's
/// request is of the tool itself: its own search not run there. Anything
/// else (a limit, the key, the model) says nothing of it.
bool refusesWebSearchTool(int status, String body) {
  if (status != 400 && status != 404 && status != 422) return false;
  // The request has no tool but this one: a tool it names is this one.
  final lower = body.toLowerCase();
  return lower.contains('tool') || lower.contains('web_search');
}
