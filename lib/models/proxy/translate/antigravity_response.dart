// After magpie's internal/gateway/codeassist.go (codeAssistDecoder) and
// CLIProxyAPI's
// internal/translator/antigravity/claude/antigravity_claude_response.go (MIT
// License; see NOTICE.md beside this file).

import 'dart:convert';
import 'dart:math';

import 'antigravity_request.dart';
import 'antigravity_signature.dart';
import 'common.dart';

/// Turns Code Assist's stream (`streamGenerateContent?alt=sse`: Gemini's
/// chunks, each in `{response}`) into Anthropic's server-sent events, one
/// line at a time ([convert]), then the end ([finish]). A function call's
/// thought signature rides in its id ([signedToolId]). A call Gemini wrote
/// out as text (`call:default_api:Bash{…}`) is made the call it meant.
class AntigravityResponseTranslator {
  AntigravityResponseTranslator({
    required this.model,
    this.store,
    this.errorFallback = 'Antigravity failed',
  });

  /// The model the reply is told to be of: the one Claude Code asked.
  final String model;
  final SignatureStore? store;

  /// Fallback message when an upstream error payload has no `message`.
  final String errorFallback;

  bool _started = false;
  bool _stopped = false;
  bool _failed = false;
  bool _tools = false;
  String _stopReason = 'end_turn';
  int _index = 0;

  /// The open block: `text`, `thinking`, or none.
  String? _open;
  String _held = '';
  ({int input, int cached, int output, int thoughts})? _usage;
  final List<String> _searchQueries = [];
  final Set<String> _seenSearchQueries = {};
  final List<Map<String, Object?>> _searchResults = [];
  final Set<String> _seenSearchUrls = {};
  int _webSearchRequests = 0;

  /// The events so far, for a reply not streamed ([message]).
  final List<Map<String, Object?>> events = [];

  /// The events of one line of the stream, as server-sent events.
  String convert(String line) {
    if (_failed || !line.startsWith('data:')) return '';
    final data = line.substring(5).trim();
    if (data.isEmpty || data == '[DONE]') return '';
    Object? json;
    try {
      json = jsonDecode(data);
    } on FormatException {
      return '';
    }
    return convertJson(json);
  }

  /// The events of one decoded Gemini / Code Assist chunk, as server-sent
  /// events. Accepts either a single JSON object or a JSON array of chunks.
  String convertJson(Object? json) {
    if (_failed) return '';
    if (json is List) {
      final buffer = StringBuffer();
      for (final item in json) {
        buffer.write(convertJson(item));
      }
      return '$buffer';
    }
    final out = <Map<String, Object?>>[];
    if (json case {'error': final Map error}) {
      _failed = true;
      out.addAll(_end());
      out.add({
        'type': 'error',
        'error': {
          'type': 'api_error',
          'message': '${error['message'] ?? errorFallback}',
        },
      });
      return _frames(out);
    }
    final chunk = switch (json) {
      {'response': final Map response} => response,
      final Map chunk => chunk,
      _ => const {},
    };
    if (chunk['usageMetadata'] case final Map usage) {
      int count(String key) => switch (usage[key]) {
        final num n => n.toInt(),
        _ => 0,
      };
      _usage = (
        input: count('promptTokenCount'),
        cached: count('cachedContentTokenCount'),
        output: count('candidatesTokenCount'),
        thoughts: count('thoughtsTokenCount'),
      );
    }
    if (!_started) {
      _started = true;
      final usage = _usage;
      out.add({
        'type': 'message_start',
        'message': {
          'id': switch (chunk['responseId']) {
            final String id when id.isNotEmpty => 'msg_$id',
            _ => 'msg_${_randomId()}',
          },
          'type': 'message',
          'role': 'assistant',
          'model': model,
          'content': <Object?>[],
          'stop_reason': null,
          'stop_sequence': null,
          // The prompt's count rides on the first chunk: told at the start,
          // as Claude Code's context meter reads it then.
          'usage': {
            'input_tokens': usage == null
                ? 0
                : max(usage.input - usage.cached, 0),
            if (usage != null && usage.cached > 0)
              'cache_read_input_tokens': usage.cached,
            'output_tokens': 0,
          },
        },
      });
    }
    for (final candidate in (chunk['candidates'] as List?) ?? const []) {
      if (candidate is! Map) continue;
      final content = candidate['content'];
      final parts = content is Map ? content['parts'] as List? : null;
      for (final part in parts ?? const []) {
        if (part is! Map) continue;
        final signature = switch (part['thoughtSignature'] ??
            part['thought_signature']) {
          final String s when s.isNotEmpty => s,
          _ => null,
        };
        if (part['functionCall'] case final Map call) {
          out
            ..addAll(_flush())
            ..addAll(
              _call(
                '${call['name'] ?? ''}',
                call['args'],
                id: switch (call['id']) {
                  final String id when id.isNotEmpty => id,
                  _ => null,
                },
                signature: signature,
              ),
            );
        } else if (part['thought'] == true) {
          out.addAll(_flush());
          if (part['text'] case final String text when text.isNotEmpty) {
            out
              ..addAll(_openBlock('thinking'))
              ..add(_delta({'type': 'thinking_delta', 'thinking': text}));
          }
          if (signature != null) {
            out
              ..addAll(_openBlock('thinking'))
              ..add(
                _delta({'type': 'signature_delta', 'signature': signature}),
              );
          }
        } else if (part['text'] case final String text) {
          out.addAll(_text(text));
        } else if (part['executableCode'] case final Map code) {
          out.addAll(
            _text(
              '\n```${'${code['language'] ?? ''}'.toLowerCase()}\n'
              '${'${code['code'] ?? ''}'.trimRight()}\n```\n',
            ),
          );
        } else if (part['codeExecutionResult'] case final Map result) {
          final output = '${result['output'] ?? ''}'.trimRight();
          if (output.isNotEmpty) out.addAll(_text('\n```\n$output\n```\n'));
        }
      }
      if (candidate['groundingMetadata'] case final Map grounding) {
        _collectGrounding(grounding);
      }
      if (candidate['finishReason'] case final String reason
          when reason.isNotEmpty && !_stopped) {
        out.addAll(_flush());
        if (!_tools &&
            (reason == 'MALFORMED_FUNCTION_CALL' ||
                reason == 'UNEXPECTED_TOOL_CALL')) {
          // The call Google would not take as one is whole in its message:
          // Claude Code can run it.
          final message = '${candidate['finishMessage'] ?? ''}';
          final at = message.indexOf(_callMarker);
          if (at >= 0) {
            final (name, args, length) = _textCall(message.substring(at));
            if (length > 0) out.addAll(_call(name, args));
          }
        }
        _stopped = true;
        _stopReason = switch (reason) {
          'MAX_TOKENS' => 'max_tokens',
          _ when _tools => 'tool_use',
          _ => 'end_turn',
        };
      }
    }
    return _frames(out);
  }

  /// The end of the reply, once the stream is: its last blocks closed, why
  /// it stopped and what it used.
  String finish() {
    if (_failed) return '';
    final out = <Map<String, Object?>>[];
    if (!_started) {
      // Nothing came: an empty reply, still a whole one.
      out.addAll(_emptyStart());
    }
    out.addAll(_end());
    return _frames(out);
  }

  /// A start for a stream that told nothing.
  List<Map<String, Object?>> _emptyStart() {
    _started = true;
    return [
      {
        'type': 'message_start',
        'message': {
          'id': 'msg_${_randomId()}',
          'type': 'message',
          'role': 'assistant',
          'model': model,
          'content': <Object?>[],
          'stop_reason': null,
          'stop_sequence': null,
          'usage': {'input_tokens': 0, 'output_tokens': 0},
        },
      },
    ];
  }

  List<Map<String, Object?>> _end() {
    if (!_started) return const [];
    final out = [..._flush(), ..._closeBlock(), ..._emitGrounding()];
    final usage = _usage;
    out
      ..add({
        'type': 'message_delta',
        'delta': {'stop_reason': _stopReason, 'stop_sequence': null},
        'usage': {
          'input_tokens': usage == null
              ? 0
              : max(usage.input - usage.cached, 0),
          if (usage != null && usage.cached > 0)
            'cache_read_input_tokens': usage.cached,
          'output_tokens': usage == null ? 0 : usage.output + usage.thoughts,
          if (usage != null && usage.thoughts > 0)
            'output_tokens_details': {'thinking_tokens': usage.thoughts},
          if (_webSearchRequests > 0)
            'server_tool_use': {'web_search_requests': _webSearchRequests},
        },
      })
      ..add({'type': 'message_stop'});
    _started = false;
    // Ended: nothing more is told.
    _failed = true;
    return out;
  }

  void _collectGrounding(Map grounding) {
    if (grounding['webSearchQueries'] case final List queries) {
      for (final item in queries) {
        if (item is String) {
          final query = item.trim();
          if (query.isNotEmpty && _seenSearchQueries.add(query)) {
            _searchQueries.add(query);
          }
        }
      }
    }
    if (grounding['groundingChunks'] case final List chunks) {
      for (final chunk in chunks) {
        if (chunk is! Map) continue;
        final web = chunk['web'];
        if (web is! Map) continue;
        final uri = '${web['uri'] ?? ''}'.trim();
        if (uri.isEmpty || !_seenSearchUrls.add(uri)) continue;
        final title = '${web['title'] ?? ''}'.trim();
        _searchResults.add({
          'type': 'web_search_result',
          'title': title.isEmpty ? uri : title,
          'url': uri,
          'page_age': null,
        });
      }
    }
  }

  List<Map<String, Object?>> _emitGrounding() {
    if (_searchQueries.isEmpty && _searchResults.isEmpty) return const [];
    final id = 'srvtoolu_${_randomId()}';
    final query = _searchQueries.join('; ');
    final results = List<Map<String, Object?>>.of(_searchResults);
    _searchQueries.clear();
    _seenSearchQueries.clear();
    _searchResults.clear();
    _seenSearchUrls.clear();
    _webSearchRequests++;
    return [
      {
        'type': 'content_block_start',
        'index': _index,
        'content_block': {
          'type': 'server_tool_use',
          'id': id,
          'name': 'web_search',
          'input': <String, Object?>{},
        },
      },
      if (query.isNotEmpty)
        _delta({
          'type': 'input_json_delta',
          'partial_json': jsonEncode({'query': query}),
        }),
      {'type': 'content_block_stop', 'index': _index++},
      {
        'type': 'content_block_start',
        'index': _index,
        'content_block': {
          'type': 'web_search_tool_result',
          'tool_use_id': id,
          'content': results,
        },
      },
      {'type': 'content_block_stop', 'index': _index++},
    ];
  }

  String _frames(List<Map<String, Object?>> out) {
    events.addAll(out);
    return out.map((event) => sseEvent('${event['type']}', event)).join();
  }

  List<Map<String, Object?>> _openBlock(String type) {
    if (_open == type) return const [];
    final closed = _closeBlock();
    _open = type;
    return [
      ...closed,
      {
        'type': 'content_block_start',
        'index': _index,
        'content_block': type == 'text'
            ? {'type': 'text', 'text': ''}
            : {'type': 'thinking', 'thinking': ''},
      },
    ];
  }

  List<Map<String, Object?>> _closeBlock() {
    if (_open == null) return const [];
    _open = null;
    return [
      {'type': 'content_block_stop', 'index': _index++},
    ];
  }

  Map<String, Object?> _delta(Map<String, Object?> delta) => {
    'type': 'content_block_delta',
    'index': _index,
    'delta': delta,
  };

  List<Map<String, Object?>> _call(
    String name,
    Object? args, {
    String? id,
    String? signature,
  }) {
    _tools = true;
    final callId = signedToolId(id ?? 'toolu_${_randomId()}', signature, store);
    final input = args is Map ? args : const <String, Object?>{};
    final closed = _closeBlock();
    final out = [
      ...closed,
      {
        'type': 'content_block_start',
        'index': _index,
        'content_block': {
          'type': 'tool_use',
          'id': callId,
          'name': antigravityToolOfCall(name),
          'input': <String, Object?>{},
        },
      },
      _delta({'type': 'input_json_delta', 'partial_json': jsonEncode(input)}),
      {'type': 'content_block_stop', 'index': _index++},
    ];
    return out;
  }

  // --- Calls written out as text ---------------------------------------------

  static const _callMarker = 'call:default_api:';

  /// How long a call written out as text may be: longer, it is text.
  static const _maxHeld = 256 << 10;

  List<Map<String, Object?>> _say(String text) => text.isEmpty
      ? const []
      : [
          ..._openBlock('text'),
          _delta({'type': 'text_delta', 'text': text}),
        ];

  /// A text part on, any call written out in it made a call.
  List<Map<String, Object?>> _text(String part) {
    var text = _held + part;
    _held = '';
    final out = <Map<String, Object?>>[];
    while (text.isNotEmpty) {
      final at = text.indexOf(_callMarker);
      if (at < 0) {
        // A tail that may be the marker's start waits for the next part.
        var k = _callMarker.length - 1;
        while (k > 0 && !text.endsWith(_callMarker.substring(0, k))) {
          k--;
        }
        out.addAll(_say(text.substring(0, text.length - k)));
        _held = text.substring(text.length - k);
        return out;
      }
      out.addAll(_say(text.substring(0, at)));
      text = text.substring(at);
      final (name, args, length) = _textCall(text);
      if (length == 0 && text.length < _maxHeld) {
        _held = text;
        return out;
      }
      if (length <= 0) {
        out.addAll(_say(_callMarker));
        text = text.substring(_callMarker.length);
        continue;
      }
      out.addAll(_call(name, args));
      text = text.substring(length);
    }
    return out;
  }

  /// Held text on as text: what comes next is not more of it.
  List<Map<String, Object?>> _flush() {
    if (_held.isEmpty) return const [];
    final held = _held;
    _held = '';
    return _say(held);
  }

  static bool _ident(int c) =>
      c == 0x5f ||
      c == 0x2d ||
      c == 0x2e ||
      (c >= 0x30 && c <= 0x39) ||
      (c >= 0x61 && c <= 0x7a) ||
      (c >= 0x41 && c <= 0x5a);

  static const _quote = '<ctrl46>';

  /// The call written out at [text]'s start: its tool, its arguments and
  /// its length; 0 where it may yet be one and is not all here, -1 where it
  /// is not one.
  static (String, Object?, int) _textCall(String text) {
    var j = _callMarker.length;
    while (j < text.length && _ident(text.codeUnitAt(j))) {
      j++;
    }
    if (j == text.length) return ('', null, 0);
    final name = text.substring(_callMarker.length, j);
    if (name.isEmpty || text[j] != '{') return ('', null, -1);
    final end = _closeBrace(text, j);
    if (end < 0) return ('', null, 0);
    final args = _textArgs(text.substring(j + 1, end));
    if (args == null) return ('', null, -1);
    return (name, args, end + 1);
  }

  static int _closeBrace(String text, int i) {
    var depth = 0;
    while (i < text.length) {
      if (text.startsWith(_quote, i)) {
        final k = text.indexOf(_quote, i + _quote.length);
        if (k < 0) return -1;
        i = k + _quote.length;
        continue;
      }
      switch (text[i]) {
        case '{':
          depth++;
        case '}':
          depth--;
          if (depth == 0) return i;
      }
      i++;
    }
    return -1;
  }

  /// A written-out call's arguments as an object: JSON's own members, or
  /// `key:value` pairs, the value quoted with `<ctrl46>`, JSON, or bare.
  static Map<String, Object?>? _textArgs(String body) {
    body = body.trim();
    if (body.isEmpty) return {};
    try {
      final json = jsonDecode('{$body}');
      if (json is Map<String, Object?>) return json;
    } on FormatException {
      // As pairs.
    }
    final out = <String, Object?>{};
    while (body.isNotEmpty) {
      var k = 0;
      while (k < body.length && _ident(body.codeUnitAt(k))) {
        k++;
      }
      if (k == 0 || k == body.length || body[k] != ':') return null;
      final key = body.substring(0, k);
      body = body.substring(k + 1);
      if (body.startsWith(_quote)) {
        final rest = body.substring(_quote.length);
        final e = rest.indexOf(_quote);
        if (e < 0) return null;
        out[key] = rest.substring(0, e);
        body = rest.substring(e + _quote.length).trimLeft();
        if (body.isNotEmpty) {
          if (body[0] != ',') return null;
          body = body.substring(1).trimLeft();
        }
      } else {
        final e = _nextKey(body);
        final value = body.substring(0, e).trim();
        try {
          out[key] = jsonDecode(value);
        } on FormatException {
          out[key] = value;
        }
        body = body.substring(e);
        if (body.isNotEmpty) body = body.substring(1).trimLeft();
      }
    }
    return out;
  }

  static int _nextKey(String text) {
    var depth = 0;
    for (var i = 0; i < text.length; i++) {
      switch (text[i]) {
        case '{' || '[':
          depth++;
        case '}' || ']':
          depth--;
        case ',':
          if (depth != 0) continue;
          var k = i + 1;
          while (k < text.length && text[k] == ' ') {
            k++;
          }
          final start = k;
          while (k < text.length && _ident(text.codeUnitAt(k))) {
            k++;
          }
          if (k > start && k < text.length && text[k] == ':') return i;
      }
    }
    return text.length;
  }

  static final _random = Random.secure();

  static String _randomId() => [
    for (var i = 0; i < 12; i++)
      'abcdefghijklmnopqrstuvwxyz0123456789'[_random.nextInt(36)],
  ].join();
}

/// The message [events] (an [AntigravityResponseTranslator]'s) make, for a
/// reply not streamed; null when they made none.
Map<String, Object?>? antigravityMessage(List<Map<String, Object?>> events) {
  Map<String, Object?>? message;
  final blocks = <int, Map<String, Object?>>{};
  final json = <int, StringBuffer>{};
  for (final event in events) {
    switch (event['type']) {
      case 'message_start':
        message = Map.of(event['message'] as Map<String, Object?>);
      case 'content_block_start':
        blocks[event['index'] as int] = Map.of(
          event['content_block'] as Map<String, Object?>,
        );
      case 'content_block_delta':
        final block = blocks[event['index'] as int];
        final delta = event['delta'] as Map<String, Object?>;
        if (block == null) continue;
        switch (delta['type']) {
          case 'text_delta':
            block['text'] = '${block['text'] ?? ''}${delta['text']}';
          case 'thinking_delta':
            block['thinking'] =
                '${block['thinking'] ?? ''}${delta['thinking']}';
          case 'signature_delta':
            block['signature'] = delta['signature'];
          case 'input_json_delta':
            json
                .putIfAbsent(event['index'] as int, StringBuffer.new)
                .write(delta['partial_json']);
        }
      case 'message_delta':
        final delta = event['delta'] as Map<String, Object?>;
        message?['stop_reason'] = delta['stop_reason'];
        message?['usage'] = event['usage'];
      case 'error':
        return null;
    }
  }
  if (message == null) return null;
  for (final MapEntry(:key, :value) in json.entries) {
    try {
      blocks[key]?['input'] = jsonDecode(value.toString());
    } on FormatException {
      blocks[key]?['input'] = <String, Object?>{};
    }
  }
  final indexes = blocks.keys.toList()..sort();
  message['content'] = [for (final i in indexes) blocks[i]];
  return message;
}

/// [events] formatted as Anthropic server-sent event frames.
String antigravitySse(List<Map<String, Object?>> events) =>
    events.map((event) => sseEvent('${event['type']}', event)).join();
