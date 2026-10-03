// Ported from CLIProxyAPI's
// internal/translator/codex/claude/codex_claude_response.go and
// codex_claude_response_web_search.go (MIT License; see NOTICE.md beside
// this file).

import 'dart:convert';

import 'json_value.dart';
import 'common.dart';
import 'responses_request.dart';
import 'util.dart';

/// Joins a reasoning item's summary parts within its one thinking block.
const _summaryPartSeparator = '\n\n';

/// A function call as it streams in.
class _FunctionCall {
  String callId = '';
  String name = '';
  int blockIndex = -1;
  String arguments = '';
  int emittedArgumentsLength = 0;
  bool receivedArgumentsDelta = false;
  bool emitInitialEmptyDelta = false;
  bool started = false;
  bool done = false;
  bool closed = false;
}

/// Turns an OpenAI Responses stream into Anthropic's server-sent events,
/// one `data:` line at a time ([convert]), for the request it answers
/// ([originalRequest], decoded or as JSON text).
///
/// Claude's content blocks follow one another, where the Responses API
/// interleaves its items: events for other items that come while a
/// function call's block is open wait for it to close.
class ResponsesResponseTranslator {
  ResponsesResponseTranslator(Object? originalRequest)
    : _request = JsonValue.of(originalRequest);

  final JsonValue _request;

  bool hasEmittedToolUse = false;
  int blockIndex = 0;
  bool _hasTextDelta = false;
  bool _textBlockOpen = false;
  bool _thinkingBlockOpen = false;
  String _thinkingSignature = '';
  bool _thinkingSummarySeen = false;
  final Set<String> _webSearchToolUseIds = {};
  final Set<String> _webSearchToolResultIds = {};
  String _lastWebSearchToolUseId = '';
  final Map<String, _FunctionCall> _functionCalls = {};
  List<_FunctionCall> _queue = [];
  _FunctionCall? _active;
  _FunctionCall? _last;
  List<String> _deferred = [];

  /// Whether function calls are still waiting on their name or close.
  bool get hasPendingFunctionCalls =>
      _functionCalls.isNotEmpty || _queue.isNotEmpty || _last != null;

  /// The events for one line of the upstream's stream, as one text; empty
  /// for a line that is not `data:`, or one whose events wait.
  String convert(String line) {
    if (!line.startsWith('data:')) return '';
    final root = JsonValue.parse(line.substring(5).trim());
    final type = root.get('type').string;
    if (_active != null && _shouldDefer(type, root)) {
      _deferred.add(line);
      return '';
    }
    final output = StringBuffer();
    switch (type) {
      case 'error':
        output.write(_streamError(root));
      case 'response.created':
        output.write(
          sseEvent('message_start', {
            'type': 'message_start',
            'message': {
              'id': root.get('response.id').string,
              'type': 'message',
              'role': 'assistant',
              'model': root.get('response.model').string,
              'stop_sequence': null,
              'usage': {'input_tokens': 0, 'output_tokens': 0},
              'content': <Object?>[],
              'stop_reason': null,
            },
          }),
        );
      case 'response.reasoning_summary_part.added':
        output.write(_stopTextBlock());
        // One thinking block for the whole reasoning item, its parts apart
        // by a blank line: only the item's end carries its signature.
        if (_thinkingBlockOpen) {
          output.write(_thinkingDelta(_summaryPartSeparator));
        } else {
          output.write(_startThinkingBlock());
        }
        _thinkingSummarySeen = true;
      case 'response.reasoning_summary_text.delta':
        output
          ..write(_stopTextBlock())
          ..write(_startThinkingBlock())
          ..write(_thinkingDelta(root.get('delta').string));
      case 'response.reasoning_summary_part.done':
        // The block stays open until the item's end brings its signature.
        break;
      case 'response.content_part.added':
        output.write(_finalizeThinkingBlock());
        if (root.get('part.type').string == 'output_text') {
          output.write(_startTextBlock());
        }
      case 'response.output_text.delta':
        _hasTextDelta = true;
        output
          ..write(_finalizeThinkingBlock())
          ..write(_startTextBlock())
          ..write(_textDelta(root.get('delta').string));
      case 'response.content_part.done':
        if (root.get('part.type').string == 'output_text') {
          output.write(_stopTextBlock());
        }
      case 'response.web_search_call.searching' ||
          'response.web_search_call.completed' ||
          'response.web_search_call.in_progress':
        // Waits for the item, with its query, at output_item.done.
        break;
      case 'response.completed' || 'response.incomplete':
        final response = root.get('response');
        output
          ..write(_finalizeThinkingBlock())
          ..write(_stopTextBlock())
          ..write(_functionCallsFromTerminal(response))
          ..write(_flushDeferred())
          ..write(_finalizeThinkingBlock())
          ..write(_stopTextBlock());
        final (input, outputTokens, cached, cacheWrite) = extractResponsesUsage(
          response.get('usage'),
        );
        final usage = <String, Object?>{
          'input_tokens': input,
          'output_tokens': outputTokens,
          if (cached > 0) 'cache_read_input_tokens': cached,
          if (cacheWrite > 0) 'cache_creation_input_tokens': cacheWrite,
        };
        _setReasoningUsage(usage, response.get('usage'));
        output
          ..write(
            sseEvent('message_delta', {
              'type': 'message_delta',
              'delta': {
                'stop_reason': mapResponsesStopReasonToClaude(
                  responsesStopReason(response),
                  hasEmittedToolUse,
                ),
                'stop_sequence': _stopSequence(response),
              },
              'usage': usage,
            }),
          )
          ..write(sseEvent('message_stop', {'type': 'message_stop'}));
      case 'response.output_item.added':
        final item = root.get('item');
        switch (item.get('type').string) {
          case 'function_call':
            output
              ..write(_finalizeThinkingBlock())
              ..write(_stopTextBlock());
            final call = _record(root, item);
            _updateIdentity(call, root, item);
            if (call.name.isNotEmpty) call.emitInitialEmptyDelta = true;
            output.write(_drainQueue());
          case 'reasoning':
            output
              ..write(_stopTextBlock())
              // An earlier reasoning item that never ended must not leak
              // its open block into this one.
              ..write(_finalizeThinkingBlock());
            _thinkingSummarySeen = false;
            // Only a fallback for items whose end has none: a snapshot
            // from before their content.
            _thinkingSignature = item.get('encrypted_content').string;
          case 'web_search_call':
          // server_tool_use waits for the item's end, with its query.
        }
      case 'response.output_item.done':
        final item = root.get('item');
        switch (item.get('type').string) {
          case 'message':
            if (_hasTextDelta) return '$output';
            final content = item.get('content');
            if (!content.isArray) return '$output';
            final text = StringBuffer();
            for (final part in content.array) {
              if (part.get('type').string != 'output_text') continue;
              text.write(part.get('text').string);
            }
            if (text.isEmpty) return '$output';
            output
              ..write(_finalizeThinkingBlock())
              ..write(_startTextBlock())
              ..write(_textDelta('$text'))
              ..write(_stopTextBlock());
            _hasTextDelta = true;
          case 'function_call':
            output
              ..write(_finalizeThinkingBlock())
              ..write(_stopTextBlock());
            final call = _callForEvent(root, item) ?? _record(root, item);
            _updateIdentity(call, root, item);
            _updateArguments(call, item.get('arguments').string, delta: false);
            call.done = true;
            output.write(_drainQueue());
          case 'reasoning':
            output.write(_stopTextBlock());
            final signature = item.get('encrypted_content').string;
            if (signature.isNotEmpty) _thinkingSignature = signature;
            output.write(
              _thinkingSummarySeen
                  ? _finalizeThinkingBlock()
                  : _finalizeSignatureOnlyThinkingBlock(),
            );
            _thinkingSignature = '';
            _thinkingSummarySeen = false;
          case 'web_search_call':
            output.write(_webSearchToolResult(root, item));
        }
      case 'response.function_call_arguments.delta':
        final call =
            _callForEvent(root, JsonValue.missing) ??
            _record(root, JsonValue.missing);
        _updateArguments(call, root.get('delta').string, delta: true);
        output.write(_bufferedArguments(call));
      case 'response.function_call_arguments.done':
        final call =
            _callForEvent(root, JsonValue.missing) ??
            _record(root, JsonValue.missing);
        _updateArguments(call, root.get('arguments').string, delta: false);
        output.write(_bufferedArguments(call));
    }
    if (_queue.isEmpty) output.write(_flushDeferred());
    return '$output';
  }

  static bool _shouldDefer(String type, JsonValue root) => switch (type) {
    'error' ||
    'response.completed' ||
    'response.incomplete' ||
    'response.function_call_arguments.delta' ||
    'response.function_call_arguments.done' => false,
    'response.output_item.added' || 'response.output_item.done' =>
      root.get('item.type').string != 'function_call',
    _ => true,
  };

  String _flushDeferred() {
    if (_deferred.isEmpty) return '';
    final events = _deferred;
    _deferred = [];
    return events.map(convert).join();
  }

  static String _streamError(JsonValue root) {
    final error = root.get('error');
    var type = error.get('type').string.trim();
    if (type.isEmpty) type = root.get('error_type').string.trim();
    if (type.isEmpty) type = 'api_error';
    final code = error.get('code').string.trim();
    var message = error.get('message').string.trim();
    if (message.isEmpty) message = root.get('message').string.trim();
    if (message.isEmpty) message = code;
    if (message.isEmpty) message = type;
    if (code == 'cyber_policy' || type == 'invalid_request') {
      type = 'invalid_request_error';
    }
    return sseEvent('error', {
      'type': 'error',
      'error': {'type': type, 'message': message},
    });
  }

  // --- Function calls -----------------------------------------------------------

  static List<String> _callKeys(JsonValue root, JsonValue item) {
    final keys = <String>[];
    void add(String key) {
      if (key.isNotEmpty && !keys.contains(key)) keys.add(key);
    }

    final outputIndex = root.get('output_index');
    if (outputIndex.exists) add('output:${outputIndex.raw}');
    if (item.get('call_id').string case final id when id.isNotEmpty) {
      add('call:$id');
    }
    if (root.get('call_id').string case final id when id.isNotEmpty) {
      add('call:$id');
    }
    if (item.get('id').string case final id when id.isNotEmpty) add('item:$id');
    if (root.get('item_id').string case final id when id.isNotEmpty) {
      add('item:$id');
    }
    return keys;
  }

  _FunctionCall? _callForKeys(List<String> keys) {
    for (final key in keys) {
      if (_functionCalls[key] case final call?) return call;
    }
    return null;
  }

  _FunctionCall? _callForEvent(JsonValue root, JsonValue item) {
    final keys = _callKeys(root, item);
    return keys.isNotEmpty ? _callForKeys(keys) : _last;
  }

  _FunctionCall _record(JsonValue root, JsonValue item) {
    final keys = _callKeys(root, item);
    var call = _callForKeys(keys);
    if (call == null) {
      call = _FunctionCall();
      _queue.add(call);
    }
    _alias(call, keys);
    _last = call;
    return call;
  }

  void _alias(_FunctionCall call, List<String> keys) {
    for (final key in keys) {
      _functionCalls[key] = call;
    }
  }

  void _updateIdentity(_FunctionCall call, JsonValue root, JsonValue item) {
    if (item.get('call_id').string case final id when id.isNotEmpty) {
      call.callId = id;
    }
    if (item.get('name').string case final name when name.isNotEmpty) {
      call.name = name;
    }
    _alias(call, _callKeys(root, item));
  }

  static void _updateArguments(
    _FunctionCall call,
    String arguments, {
    required bool delta,
  }) {
    if (arguments.isEmpty) return;
    if (delta) {
      call
        ..arguments += arguments
        ..receivedArgumentsDelta = true;
    } else if (!call.receivedArgumentsDelta ||
        arguments.startsWith(call.arguments)) {
      call.arguments = arguments;
    }
  }

  String _bufferedArguments(_FunctionCall call) {
    if (!identical(_active, call) || !call.started || call.closed) return '';
    if (call.emittedArgumentsLength >= call.arguments.length) return '';
    final delta = call.arguments.substring(call.emittedArgumentsLength);
    call.emittedArgumentsLength = call.arguments.length;
    return _argumentDelta(delta, call.blockIndex);
  }

  static String _argumentDelta(String partialJson, int index) =>
      sseEvent('content_block_delta', {
        'type': 'content_block_delta',
        'index': index,
        'delta': {'type': 'input_json_delta', 'partial_json': partialJson},
      });

  /// Starts the queued calls in turn, each once the one before is done.
  String _drainQueue() {
    final output = StringBuffer();
    while (true) {
      if (_active case final active?) {
        output.write(_bufferedArguments(active));
        if (!active.done) return '$output';
        output.write(_blockStop(active.blockIndex));
        if (blockIndex <= active.blockIndex) blockIndex = active.blockIndex + 1;
        active.closed = true;
        _active = null;
        _queue.remove(active);
      }
      while (_queue.isNotEmpty && _queue.first.closed) {
        _queue.removeAt(0);
      }
      if (_queue.isEmpty) return '$output';
      final call = _queue.first;
      if (call.name.isEmpty) return '$output';
      call.blockIndex = blockIndex;
      output.write(
        sseEvent('content_block_start', {
          'type': 'content_block_start',
          'index': call.blockIndex,
          'content_block': {
            'type': 'tool_use',
            'id': shortenCallIdIfNeeded(sanitizeClaudeToolId(call.callId)),
            'name': _toolUseName(call.name),
            'input': <String, Object?>{},
          },
        }),
      );
      if (call.emitInitialEmptyDelta) {
        output.write(_argumentDelta('', call.blockIndex));
      }
      call.started = true;
      _active = call;
      hasEmittedToolUse = true;
      output.write(_bufferedArguments(call));
    }
  }

  String _functionCallsFromTerminal(JsonValue response) {
    for (final (index, item) in response.get('output').array.indexed) {
      if (item.get('type').string != 'function_call') continue;
      final keys = _callKeys(JsonValue.missing, item);
      final itemOutputIndex = item.get('output_index');
      void add(String key) {
        if (!keys.contains(key)) keys.add(key);
      }

      if (itemOutputIndex.exists) add('output:${itemOutputIndex.raw}');
      add('output:$index');
      var call = _callForKeys(keys);
      if (call == null) {
        call = _FunctionCall();
        _queue.add(call);
      }
      _alias(call, keys);
      _updateIdentity(call, JsonValue.missing, item);
      _updateArguments(call, item.get('arguments').string, delta: false);
      call.done = true;
    }
    final queued = <_FunctionCall>[];
    for (final call in _queue) {
      if (call.closed) continue;
      if (call.name.isEmpty) {
        // Never named: it cannot be told to the client.
        call.closed = true;
        continue;
      }
      queued.add(call..done = true);
    }
    _queue = queued;
    final output = _drainQueue();
    _functionCalls.clear();
    _queue = [];
    _active = null;
    _last = null;
    return output;
  }

  String _toolUseName(String name) =>
      buildReverseToolNameMap(_request)[name] ?? name;

  // --- Blocks ---------------------------------------------------------------------

  static String _blockStop(int index) => sseEvent('content_block_stop', {
    'type': 'content_block_stop',
    'index': index,
  });

  String _textDelta(String text) => sseEvent('content_block_delta', {
    'type': 'content_block_delta',
    'index': blockIndex,
    'delta': {'type': 'text_delta', 'text': text},
  });

  String _startTextBlock() {
    if (_textBlockOpen) return '';
    _textBlockOpen = true;
    return sseEvent('content_block_start', {
      'type': 'content_block_start',
      'index': blockIndex,
      'content_block': {'type': 'text', 'text': ''},
    });
  }

  String _stopTextBlock() {
    if (!_textBlockOpen) return '';
    final event = _blockStop(blockIndex);
    _textBlockOpen = false;
    blockIndex++;
    return event;
  }

  String _startThinkingBlock() {
    if (_thinkingBlockOpen) return '';
    _thinkingBlockOpen = true;
    return sseEvent('content_block_start', {
      'type': 'content_block_start',
      'index': blockIndex,
      'content_block': {'type': 'thinking', 'thinking': ''},
    });
  }

  String _thinkingDelta(String text) {
    if (text.isEmpty) return '';
    return sseEvent('content_block_delta', {
      'type': 'content_block_delta',
      'index': blockIndex,
      'delta': {'type': 'thinking_delta', 'thinking': text},
    });
  }

  String _finalizeSignatureOnlyThinkingBlock() {
    if (_thinkingSignature.isEmpty) return '';
    return _startThinkingBlock() + _finalizeThinkingBlock();
  }

  String _finalizeThinkingBlock() {
    if (!_thinkingBlockOpen) return '';
    final output = StringBuffer();
    if (_thinkingSignature.isNotEmpty) {
      output.write(
        sseEvent('content_block_delta', {
          'type': 'content_block_delta',
          'index': blockIndex,
          'delta': {'type': 'signature_delta', 'signature': _thinkingSignature},
        }),
      );
    }
    output.write(_blockStop(blockIndex));
    blockIndex++;
    _thinkingBlockOpen = false;
    return '$output';
  }

  // --- Web search -------------------------------------------------------------------

  String _webSearchServerToolUse(JsonValue root, JsonValue item) {
    final id = _webSearchToolUseId(root, item);
    if (id.isEmpty) return '';
    final query = webSearchQuery(root, item);
    final alreadyStarted = _webSearchToolUseIds.contains(id);
    if (alreadyStarted && query.isEmpty) return '';
    final output = StringBuffer();
    if (!alreadyStarted) {
      output
        ..write(_stopTextBlock())
        ..write(_finalizeThinkingBlock())
        ..write(
          sseEvent('content_block_start', {
            'type': 'content_block_start',
            'index': blockIndex,
            'content_block': {
              'type': 'server_tool_use',
              'id': id,
              'name': 'web_search',
              'input': <String, Object?>{},
            },
          }),
        );
    }
    if (query.isNotEmpty) {
      output.write(_argumentDelta(jsonEncode({'query': query}), blockIndex));
    }
    if (!alreadyStarted) {
      output.write(_blockStop(blockIndex));
      _webSearchToolUseIds.add(id);
      blockIndex++;
    }
    return '$output';
  }

  String _webSearchToolResult(JsonValue root, JsonValue item) {
    final id = _webSearchToolUseId(root, item);
    if (id.isEmpty) return '';
    final output = StringBuffer(_webSearchServerToolUse(root, item));
    if (_webSearchToolResultIds.contains(id)) return '$output';
    final content = webSearchResultContent(root, item);
    if (webSearchQuery(root, item).isEmpty &&
        (content == null || content.isEmpty) &&
        !item.get('action').exists) {
      return '$output';
    }
    output
      ..write(
        sseEvent('content_block_start', {
          'type': 'content_block_start',
          'index': blockIndex,
          'content_block': {
            'type': 'web_search_tool_result',
            'tool_use_id': id,
            'content': content ?? <Object?>[],
          },
        }),
      )
      ..write(_blockStop(blockIndex));
    _webSearchToolResultIds.add(id);
    blockIndex++;
    if (id == _lastWebSearchToolUseId) _lastWebSearchToolUseId = '';
    return '$output';
  }

  String _webSearchToolUseId(JsonValue root, JsonValue item) {
    for (final path in const ['id', 'output_item_id', 'call_id']) {
      for (final from in [item, root]) {
        final value = from.get(path).string.trim();
        if (value.isNotEmpty) return value;
      }
    }
    if (_lastWebSearchToolUseId.isNotEmpty) return _lastWebSearchToolUseId;
    for (final from in [item, root]) {
      final value = from.get('item_id').string.trim();
      if (value.isNotEmpty) return value;
    }
    return _lastWebSearchToolUseId = 'web_search_$blockIndex';
  }
}

/// A web search item's query.
String webSearchQuery(JsonValue root, JsonValue item) {
  for (final path in const ['action.query', 'query', 'input.query']) {
    for (final from in [item, root]) {
      final value = from.get(path).string.trim();
      if (value.isNotEmpty) return value;
    }
  }
  return '';
}

/// A web search item's results as Claude's `web_search_result`s: null
/// when it has no results list.
List<Map<String, Object?>>? webSearchResultContent(
  JsonValue root,
  JsonValue item,
) {
  var results = item.get('results');
  if (!results.isArray) results = root.get('results');
  if (!results.isArray) return null;
  return [
    for (final result in results.array)
      if (result.get('url').string.trim() case final url when url.isNotEmpty)
        {
          'type': 'web_search_result',
          'title': switch (result.get('title').string.trim()) {
            '' => url,
            final title => title,
          },
          'url': url,
          'page_age': null,
        },
  ];
}

/// A whole Responses reply (its `response.completed` event) as an
/// Anthropic message, for a request that did not stream; null for another
/// event.
Map<String, Object?>? convertResponsesResponseToClaudeNonStream(
  Object? originalRequest,
  Object? event,
) {
  final names = buildReverseToolNameMap(JsonValue.of(originalRequest));
  final root = JsonValue.of(event);
  final type = root.get('type').string;
  if (type != 'response.completed' && type != 'response.incomplete') {
    return null;
  }
  final response = root.get('response');
  if (!response.exists) return null;
  final (input, output, cached, cacheWrite) = extractResponsesUsage(
    response.get('usage'),
  );
  final usage = <String, Object?>{
    'input_tokens': input,
    'output_tokens': output,
    if (cached > 0) 'cache_read_input_tokens': cached,
    if (cacheWrite > 0) 'cache_creation_input_tokens': cacheWrite,
  };
  _setReasoningUsage(usage, response.get('usage'));
  final out = <String, Object?>{
    'id': response.get('id').string,
    'type': 'message',
    'role': 'assistant',
    'model': response.get('model').string,
    'content': <Object?>[],
    'stop_reason': null,
    'stop_sequence': null,
    'usage': usage,
  };
  var hasToolCall = false;
  final seen = <String>{};
  final blocks = <Map<String, Object?>>[];
  String partsText(JsonValue parts) {
    if (!parts.isArray) return parts.string;
    return parts.array.map((part) {
      final text = part.get('text');
      return text.exists ? text.string : part.string;
    }).join();
  }

  for (final item in response.get('output').array) {
    switch (item.get('type').string) {
      case 'reasoning':
        final signature = item.get('encrypted_content').string;
        var thinking = '';
        final summary = item.get('summary');
        if (summary.exists) thinking = partsText(summary);
        if (thinking.isEmpty) {
          final content = item.get('content');
          if (content.exists) thinking = partsText(content);
        }
        if (thinking.isNotEmpty || signature.isNotEmpty) {
          blocks.add({
            'type': 'thinking',
            'thinking': thinking,
            if (signature.isNotEmpty) 'signature': signature,
          });
        }
      case 'message':
        final content = item.get('content');
        if (content.isArray) {
          for (final part in content.array) {
            if (part.get('type').string != 'output_text') continue;
            final text = part.get('text').string;
            if (text.isNotEmpty) blocks.add({'type': 'text', 'text': text});
          }
        } else if (content.exists && content.string.isNotEmpty) {
          blocks.add({'type': 'text', 'text': content.string});
        }
      case 'web_search_call':
        blocks.addAll(_webSearchNonStreamBlocks(item, seen));
      case 'function_call':
        hasToolCall = true;
        final name = item.get('name').string;
        final args = JsonValue.parse(item.get('arguments').string);
        blocks.add({
          'type': 'tool_use',
          'id': shortenCallIdIfNeeded(
            sanitizeClaudeToolId(item.get('call_id').string),
          ),
          'name': names[name] ?? name,
          'input': args.isObject ? args.value : <String, Object?>{},
        });
    }
  }
  if (blocks.isNotEmpty) out['content'] = blocks;
  out['stop_reason'] = mapResponsesStopReasonToClaude(
    responsesStopReason(response),
    hasToolCall,
  );
  if (_stopSequence(response) case final sequence?) {
    out['stop_sequence'] = sequence;
  }
  return out;
}

List<Map<String, Object?>> _webSearchNonStreamBlocks(
  JsonValue item,
  Set<String> seen,
) {
  final id = item.get('id').string.trim();
  if (id.isEmpty || seen.contains(id)) return const [];
  final query = webSearchQuery(JsonValue.missing, item);
  final content = webSearchResultContent(JsonValue.missing, item);
  if (query.isEmpty && content == null) return const [];
  seen.add(id);
  return [
    {
      'type': 'server_tool_use',
      'id': id,
      'name': 'web_search',
      'input': query.isEmpty ? <String, Object?>{} : {'query': query},
    },
    {
      'type': 'web_search_tool_result',
      'tool_use_id': id,
      'content': content ?? <Object?>[],
    },
  ];
}

/// Why a response stopped, as the Responses API says.
String responsesStopReason(JsonValue response) {
  final stop = response.get('stop_reason');
  if (stop.exists && stop.string.isNotEmpty) {
    if (stop.string == 'stop' && _stopSequence(response) != null) {
      return 'stop_sequence';
    }
    return stop.string;
  }
  final reason = response.get('incomplete_details.reason');
  if (reason.exists && reason.string.isNotEmpty) return reason.string;
  if (_stopSequence(response) != null) return 'stop_sequence';
  return '';
}

/// The Responses API's stop reasons as Anthropic's.
String mapResponsesStopReasonToClaude(String reason, bool hasToolCall) {
  if (hasToolCall) return 'tool_use';
  return switch (reason) {
    '' || 'stop' || 'completed' => 'end_turn',
    'max_tokens' || 'max_output_tokens' => 'max_tokens',
    'tool_use' || 'tool_calls' || 'function_call' => 'end_turn',
    'end_turn' ||
    'stop_sequence' ||
    'pause_turn' ||
    'refusal' ||
    'model_context_window_exceeded' => reason,
    'content_filter' => 'refusal',
    _ => 'end_turn',
  };
}

Object? _stopSequence(JsonValue response) {
  final sequence = response.get('stop_sequence');
  return sequence.exists && sequence.string.isNotEmpty ? sequence.value : null;
}

/// The usage of a Responses reply: input tokens (less those read from or
/// written to the cache), output tokens, cache reads, cache writes.
(int, int, int, int) extractResponsesUsage(JsonValue usage) {
  if (!usage.exists || usage.isNull) return (0, 0, 0, 0);
  var input = usage.get('input_tokens').integer;
  final output = usage.get('output_tokens').integer;
  final cached = usage.get('input_tokens_details.cached_tokens').integer;
  var cacheWrite = usage.get('input_tokens_details.cache_write_tokens').integer;
  if (cacheWrite <= 0) {
    cacheWrite = usage
        .get('input_tokens_details.cache_creation_tokens')
        .integer;
  }
  // One at a time, so that two huge counts cannot overflow.
  for (final deduct in [cached, cacheWrite]) {
    if (deduct > 0) input = input >= deduct ? input - deduct : 0;
  }
  return (input < 0 ? 0 : input, output, cached, cacheWrite);
}

/// The reasoning tokens, as `output_tokens_details.thinking_tokens`, at
/// most the output tokens.
void _setReasoningUsage(Map<String, Object?> usage, JsonValue source) {
  final detail = source.get('output_tokens_details.reasoning_tokens');
  if (detail.type != JsonType.number || detail.number < 0) return;
  final output = source.get('output_tokens').integer.clamp(0, 1 << 62);
  usage['output_tokens_details'] = {
    'thinking_tokens': detail.number >= output ? output : detail.integer,
  };
}
