// Ported from CLIProxyAPI's
// internal/translator/openai/claude/openai_claude_response.go (MIT License;
// see NOTICE.md beside this file).

import 'dart:convert';

import 'json_value.dart';
import 'common.dart';
import 'util.dart';

/// A tool call as it streams in.
class _ToolCallAccumulator {
  String id = '';
  String name = '';
  final StringBuffer arguments = StringBuffer();

  /// Whether its `content_block_start` went out.
  bool startEmitted = false;
}

/// Text or thinking that came while a tool call's block was open: Claude's
/// blocks follow one another, so it waits for the call to end.
class _InterleavedChunk {
  _InterleavedChunk(this.type, this.text);

  final String type;
  String text;
}

/// Turns an OpenAI Chat Completions stream into Anthropic's server-sent
/// events, one `data:` line at a time ([convert]), for the request it
/// answers ([originalRequest], decoded or as JSON text).
class OpenAIChatResponseTranslator {
  OpenAIChatResponseTranslator(Object? originalRequest)
    : _request = JsonValue.of(originalRequest);

  final JsonValue _request;

  String messageId = '';
  String model = '';
  int createdAt = 0;
  Map<String, String>? _toolNameMap;
  bool _toolNameMapRead = false;

  /// Once a `tool_use` block's start went out: what the upstream's
  /// tool_calls alone say could leave a tool_use stop with none announced.
  bool sawToolCall = false;
  final StringBuffer _content = StringBuffer();
  Map<int, _ToolCallAccumulator>? _toolCalls;
  bool _textStarted = false;
  bool _thinkingStarted = false;
  String finishReason = '';
  bool _blocksStopped = false;
  bool messageDeltaSent = false;
  bool _messageStarted = false;
  bool messageStopSent = false;
  final Map<int, int> _toolBlockIndexes = {};
  int _textIndex = -1;
  int _thinkingIndex = -1;
  int _nextIndex = 0;
  int _openToolCall = -1;
  List<_InterleavedChunk> _interleaved = [];
  int _inputTokens = 0;
  int _outputTokens = 0;
  int _cachedTokens = 0;
  int _cacheWriteTokens = 0;

  /// The events for one line of the upstream's stream: none for a line
  /// that is not `data:`.
  List<String> convert(String line) {
    if (!line.startsWith('data:')) return const [];
    final data = line.substring(5).trim();
    if (!_toolNameMapRead) {
      _toolNameMapRead = true;
      _toolNameMap = toolNameMapFromClaudeRequest(_request);
    }
    if (data == '[DONE]') return _done();
    final stream = _request.get('stream');
    if (!stream.exists || stream.value == false) {
      return [jsonEncode(_nonStreaming(JsonValue.parse(data)))];
    }
    return _chunk(JsonValue.parse(data));
  }

  bool _hasValidToolCallArguments() {
    final calls = _toolCalls;
    if (calls == null || calls.isEmpty) return true;
    for (final call in calls.values) {
      if (!call.startEmitted &&
          call.name.isEmpty &&
          call.id.isEmpty &&
          call.arguments.isEmpty) {
        continue;
      }
      if (call.arguments.isEmpty) continue;
      final args = call.arguments.toString().trim();
      if (args.isEmpty) return false;
      if (args == '{}') continue;
      final fixed = JsonValue.parse(fixJson(args));
      if (!fixed.isObject) return false;
    }
    return true;
  }

  String _effectiveFinishReason() {
    if (finishReason == 'length' || finishReason == 'content_filter') {
      return finishReason;
    }
    if (sawToolCall) {
      return _hasValidToolCallArguments() ? 'tool_calls' : 'length';
    }
    return finishReason;
  }

  String _terminalFinishReason() => switch (_effectiveFinishReason()) {
    '' => 'stop',
    final reason => reason,
  };

  List<String> _chunk(JsonValue root) {
    final results = <String>[];
    if (messageId.isEmpty) messageId = root.get('id').string;
    if (model.isEmpty) model = root.get('model').string;
    if (createdAt == 0) createdAt = root.get('created').integer;

    final delta = root.get('choices.0.delta');
    if (delta.exists) {
      // On the first chunk, role or not: some providers start with tool
      // calls and no role.
      if (!_messageStarted) {
        results.add(
          sseEvent('message_start', {
            'type': 'message_start',
            'message': {
              'id': messageId,
              'type': 'message',
              'role': 'assistant',
              'model': model,
              'content': <Object?>[],
              'stop_reason': null,
              'stop_sequence': null,
              'usage': {'input_tokens': 0, 'output_tokens': 0},
            },
          }),
        );
        _messageStarted = true;
      }

      for (final text in collectReasoningTexts(delta)) {
        if (text.isEmpty) continue;
        if (_openToolCall != -1) {
          _buffer('thinking', text);
        } else {
          _stopText(results);
          if (!_thinkingStarted) {
            if (_thinkingIndex == -1) _thinkingIndex = _nextIndex++;
            results.add(
              sseEvent('content_block_start', {
                'type': 'content_block_start',
                'index': _thinkingIndex,
                'content_block': {'type': 'thinking', 'thinking': ''},
              }),
            );
            _thinkingStarted = true;
          }
          results.add(
            sseEvent('content_block_delta', {
              'type': 'content_block_delta',
              'index': _thinkingIndex,
              'delta': {'type': 'thinking_delta', 'thinking': text},
            }),
          );
        }
      }

      final content = delta.get('content');
      if (content.exists && content.string.isNotEmpty) {
        final text = content.string;
        if (_openToolCall != -1) {
          // A tool call's block is open: the text waits, so that blocks
          // follow one another.
          _buffer('text', text);
          _content.write(text);
        } else {
          if (!_textStarted) {
            _stopThinking(results);
            if (_textIndex == -1) _textIndex = _nextIndex++;
            results.add(
              sseEvent('content_block_start', {
                'type': 'content_block_start',
                'index': _textIndex,
                'content_block': {'type': 'text', 'text': ''},
              }),
            );
            _textStarted = true;
          }
          results.add(
            sseEvent('content_block_delta', {
              'type': 'content_block_delta',
              'index': _textIndex,
              'delta': {'type': 'text_delta', 'text': text},
            }),
          );
          _content.write(text);
        }
      }

      final toolCalls = delta.get('tool_calls');
      if (toolCalls.isArray) {
        final accumulators = _toolCalls ??= {};
        for (final (arrayIndex, call) in toolCalls.array.indexed) {
          final indexValue = call.get('index');
          final index = indexValue.exists ? indexValue.integer : arrayIndex;
          final accumulator = accumulators.putIfAbsent(
            index,
            _ToolCallAccumulator.new,
          );
          // A string, and not empty: a malformed field must not replace a
          // good id.
          final id = call.get('id');
          if (id.isString && id.string.isNotEmpty) accumulator.id = id.string;
          final function = call.get('function');
          if (function.exists) {
            // Named until its start went out: some upstreams repeat it, or
            // send it empty.
            if (!accumulator.startEmitted) {
              final name = function.get('name');
              if (name.isString && name.string.isNotEmpty) {
                accumulator.name = mapToolName(_toolNameMap, name.string);
              }
            }
            final args = function.get('arguments');
            if (args.exists && args.string.isNotEmpty) {
              accumulator.arguments.write(args.string);
            }
          }
          // On every chunk: some upstreams send the name and the id apart.
          // Started now only if no other call's block is open.
          if (!accumulator.startEmitted &&
              accumulator.name.isNotEmpty &&
              accumulator.id.isNotEmpty &&
              !_blocksStopped &&
              _openToolCall == -1) {
            _emitToolUseStart(index, accumulator, results);
          }
        }
      }
    }

    // The reason it finished; message_delta waits for the usage, or [DONE].
    final reason = root.get('choices.0.finish_reason');
    if (reason.exists && reason.string.isNotEmpty) {
      final value = reason.string;
      if (value == 'length') {
        finishReason = 'length';
      } else if (value == 'content_filter') {
        finishReason = 'content_filter';
      } else if (sawToolCall) {
        finishReason = _hasValidToolCallArguments() ? 'tool_calls' : 'length';
      } else if (value == 'tool_calls') {
        finishReason = 'stop';
      } else {
        finishReason = value;
      }
      _finalizeBlocks(results);
    }

    final usage = root.get('usage');
    final hasUsage = usage.exists && !usage.isNull;
    if (hasUsage) {
      final (input, output, cached, cacheWrite) = extractOpenAIUsage(usage);
      _inputTokens = input;
      _outputTokens = output;
      _cachedTokens = cached;
      _cacheWriteTokens = cacheWrite;
    }

    // Done once it said why it finished, or a usage-only chunk came after
    // what it sent.
    final trailingUsage =
        hasUsage &&
        !root.get('choices.0').exists &&
        (finishReason.isNotEmpty ||
            sawToolCall ||
            _textStarted ||
            _thinkingStarted ||
            _content.isNotEmpty ||
            _interleaved.isNotEmpty);
    if (!messageDeltaSent &&
        (finishReason.isNotEmpty || trailingUsage) &&
        hasUsage) {
      _finalizeBlocks(results);
      _emitMessageDelta(results);
      _emitMessageStop(results);
    }
    return results;
  }

  List<String> _done() {
    final results = <String>[];
    _finalizeBlocks(results);
    if (!messageDeltaSent) _emitMessageDelta(results);
    _emitMessageStop(results);
    return results;
  }

  void _buffer(String type, String text) {
    if (_interleaved.lastOrNull case final last? when last.type == type) {
      last.text += text;
    } else {
      _interleaved.add(_InterleavedChunk(type, text));
    }
  }

  int _toolBlockIndex(int toolIndex) =>
      _toolBlockIndexes.putIfAbsent(toolIndex, () => _nextIndex++);

  void _stopThinking(List<String> results) {
    if (!_thinkingStarted) return;
    results.add(_blockStop(_thinkingIndex));
    _thinkingStarted = false;
    _thinkingIndex = -1;
  }

  void _stopText(List<String> results) {
    if (!_textStarted) return;
    results.add(_blockStop(_textIndex));
    _textStarted = false;
    _textIndex = -1;
  }

  static String _blockStop(int index) => sseEvent('content_block_stop', {
    'type': 'content_block_stop',
    'index': index,
  });

  void _emitMessageStop(List<String> results) {
    if (messageStopSent) return;
    results.add(sseEvent('message_stop', {'type': 'message_stop'}));
    messageStopSent = true;
  }

  void _emitToolUseStart(
    int toolIndex,
    _ToolCallAccumulator accumulator,
    List<String> results,
  ) {
    _stopThinking(results);
    _stopText(results);
    results.add(
      sseEvent('content_block_start', {
        'type': 'content_block_start',
        'index': _toolBlockIndex(toolIndex),
        'content_block': {
          'type': 'tool_use',
          'id': sanitizeClaudeToolId(accumulator.id),
          'name': accumulator.name,
          'input': <String, Object?>{},
        },
      }),
    );
    accumulator.startEmitted = true;
    sawToolCall = true;
    _openToolCall = toolIndex;
  }

  /// Starts a call that never started mid-stream. A call some upstreams
  /// leave nameless for the whole stream is named `tool_<index>` rather
  /// than dropped, which would lose it and loop the agent. False when it
  /// has nothing to go on.
  bool _emitBelatedToolUseStart(
    int toolIndex,
    _ToolCallAccumulator accumulator,
    List<String> results,
  ) {
    if (accumulator.startEmitted) return true;
    if (accumulator.name.isEmpty &&
        accumulator.id.isEmpty &&
        accumulator.arguments.isEmpty) {
      return false;
    }
    if (accumulator.name.isEmpty) accumulator.name = 'tool_$toolIndex';
    _emitToolUseStart(toolIndex, accumulator, results);
    return true;
  }

  void _finalizeToolCall(int toolIndex, List<String> results) {
    final accumulator = _toolCalls?[toolIndex];
    if (accumulator == null) return;
    if (!accumulator.startEmitted &&
        !_emitBelatedToolUseStart(toolIndex, accumulator, results)) {
      return;
    }
    final index = _toolBlockIndex(toolIndex);
    // All its arguments in one delta.
    if (accumulator.arguments.isNotEmpty) {
      results.add(
        sseEvent('content_block_delta', {
          'type': 'content_block_delta',
          'index': index,
          'delta': {
            'type': 'input_json_delta',
            'partial_json': fixJson('${accumulator.arguments}'),
          },
        }),
      );
    }
    results.add(_blockStop(index));
    _toolBlockIndexes.remove(toolIndex);
    _openToolCall = -1;
  }

  void _emitInterleaved(List<String> results) {
    if (_interleaved.isEmpty) return;
    for (final chunk in _interleaved) {
      if (chunk.text.isEmpty) continue;
      final index = _nextIndex++;
      final (block, delta) = switch (chunk.type) {
        'thinking' => (
          {'type': 'thinking', 'thinking': ''},
          {'type': 'thinking_delta', 'thinking': chunk.text},
        ),
        _ => (
          {'type': 'text', 'text': ''},
          {'type': 'text_delta', 'text': chunk.text},
        ),
      };
      results
        ..add(
          sseEvent('content_block_start', {
            'type': 'content_block_start',
            'index': index,
            'content_block': block,
          }),
        )
        ..add(
          sseEvent('content_block_delta', {
            'type': 'content_block_delta',
            'index': index,
            'delta': delta,
          }),
        )
        ..add(_blockStop(index));
    }
    _interleaved = [];
  }

  void _finalizeBlocks(List<String> results) {
    _stopThinking(results);
    _stopText(results);
    if (_blocksStopped) return;
    if (_openToolCall != -1) _finalizeToolCall(_openToolCall, results);
    final calls = _toolCalls;
    if (calls != null) {
      for (final index in calls.keys.toList()..sort()) {
        if (calls[index]!.startEmitted) continue;
        _finalizeToolCall(index, results);
      }
    }
    _blocksStopped = true;
    _emitInterleaved(results);
  }

  void _emitMessageDelta(List<String> results) {
    if (messageDeltaSent) return;
    results.add(
      sseEvent('message_delta', {
        'type': 'message_delta',
        'delta': {
          'stop_reason': mapOpenAIFinishReasonToAnthropic(
            _terminalFinishReason(),
          ),
          'stop_sequence': null,
        },
        'usage': _usage(
          _inputTokens,
          _outputTokens,
          _cachedTokens,
          _cacheWriteTokens,
        ),
      }),
    );
    messageDeltaSent = true;
  }

  /// A whole reply, for a request that did not stream, as it comes line by
  /// line.
  static Map<String, Object?> _nonStreaming(JsonValue root) {
    final out = _emptyMessage(root);
    final choices = root.get('choices');
    if (choices.isArray && choices.array.isNotEmpty) {
      final choice = choices.array.first;
      final blocks = <Map<String, Object?>>[
        for (final text in collectReasoningTexts(choice.get('message')))
          if (text.isNotEmpty) {'type': 'thinking', 'thinking': text},
      ];
      final content = choice.get('message.content');
      if (content.exists && content.string.isNotEmpty) {
        blocks.add({'type': 'text', 'text': content.string});
      }
      final toolCalls = choice.get('message.tool_calls');
      if (toolCalls.isArray) {
        for (final call in toolCalls.array) {
          blocks.add({
            'type': 'tool_use',
            'id': sanitizeClaudeToolId(call.get('id').string),
            'name': call.get('function.name').string,
            'input': _arguments(call.get('function.arguments').string),
          });
        }
      }
      if (blocks.isNotEmpty) out['content'] = blocks;
      final reason = choice.get('finish_reason');
      if (reason.exists) {
        out['stop_reason'] = mapOpenAIFinishReasonToAnthropic(reason.string);
      }
    }
    final usage = root.get('usage');
    if (usage.exists) out['usage'] = _usageOf(usage);
    return out;
  }
}

/// A whole OpenAI Chat Completions reply as an Anthropic message, for a
/// request that did not stream ([originalRequest], for its tools' names).
Map<String, Object?> convertOpenAIResponseToClaudeNonStream(
  Object? originalRequest,
  Object? response,
) {
  final root = JsonValue.of(response);
  final toolNameMap = toolNameMapFromClaudeRequest(
    JsonValue.of(originalRequest),
  );
  final out = _emptyMessage(root);
  var hasToolCall = false;
  var stopReasonSet = false;
  final blocks = <Map<String, Object?>>[];

  Map<String, Object?> toolUse(JsonValue call) {
    hasToolCall = true;
    return {
      'type': 'tool_use',
      'id': sanitizeClaudeToolId(call.get('id').string),
      'name': mapToolName(toolNameMap, call.get('function.name').string),
      'input': _arguments(call.get('function.arguments').string),
    };
  }

  final choices = root.get('choices');
  if (choices.isArray && choices.array.isNotEmpty) {
    final choice = choices.array.first;
    final reason = choice.get('finish_reason');
    if (reason.exists) {
      out['stop_reason'] = mapOpenAIFinishReasonToAnthropic(reason.string);
      stopReasonSet = true;
    }
    final message = choice.get('message');
    if (message.exists) {
      final content = message.get('content');
      if (content.exists) {
        if (content.isArray) {
          final text = StringBuffer();
          final thinking = StringBuffer();
          void flushText() {
            if (text.isEmpty) return;
            blocks.add({'type': 'text', 'text': '$text'});
            text.clear();
          }

          void flushThinking() {
            if (thinking.isEmpty) return;
            blocks.add({'type': 'thinking', 'thinking': '$thinking'});
            thinking.clear();
          }

          for (final item in content.array) {
            switch (item.get('type').string) {
              case 'text':
                flushThinking();
                text.write(item.get('text').string);
              case 'tool_calls':
                flushThinking();
                flushText();
                final calls = item.get('tool_calls');
                if (calls.isArray) {
                  for (final call in calls.array) {
                    blocks.add(toolUse(call));
                  }
                }
              case 'reasoning':
                flushText();
                final reasoning = item.get('text');
                if (reasoning.exists) thinking.write(reasoning.string);
              default:
                flushThinking();
                flushText();
            }
          }
          flushThinking();
          flushText();
        } else if (content.isString && content.string.isNotEmpty) {
          blocks.add({'type': 'text', 'text': content.string});
        }
      }
      for (final text in collectReasoningTexts(message)) {
        if (text.isNotEmpty) blocks.add({'type': 'thinking', 'thinking': text});
      }
      final calls = message.get('tool_calls');
      if (calls.isArray) {
        for (final call in calls.array) {
          blocks.add(toolUse(call));
        }
      }
    }
  }
  if (blocks.isNotEmpty) out['content'] = blocks;
  final usage = root.get('usage');
  if (usage.exists) out['usage'] = _usageOf(usage);
  if (!stopReasonSet) {
    out['stop_reason'] = hasToolCall ? 'tool_use' : 'end_turn';
  }
  return out;
}

Map<String, Object?> _emptyMessage(JsonValue root) => {
  'id': root.get('id').string,
  'type': 'message',
  'role': 'assistant',
  'model': root.get('model').string,
  'content': <Object?>[],
  'stop_reason': null,
  'stop_sequence': null,
  'usage': {'input_tokens': 0, 'output_tokens': 0},
};

/// Tool arguments as an input object: `{}` unless they parse as one.
Map<String, Object?> _arguments(String raw) {
  final fixed = fixJson(raw);
  if (fixed.isEmpty) return {};
  final value = JsonValue.parse(fixed);
  return value.isObject ? (value.value! as Map).cast<String, Object?>() : {};
}

Map<String, Object?> _usageOf(JsonValue usage) {
  final (input, output, cached, cacheWrite) = extractOpenAIUsage(usage);
  return _usage(input, output, cached, cacheWrite);
}

Map<String, Object?> _usage(
  int input,
  int output,
  int cached,
  int cacheWrite,
) => {
  'input_tokens': input,
  'output_tokens': output,
  if (cached > 0) 'cache_read_input_tokens': cached,
  if (cacheWrite > 0) 'cache_creation_input_tokens': cacheWrite,
};

/// OpenAI's finish reasons as Anthropic's stop reasons.
String mapOpenAIFinishReasonToAnthropic(String reason) => switch (reason) {
  'stop' => 'end_turn',
  'length' => 'max_tokens',
  'tool_calls' => 'tool_use',
  // Anthropic has none like it.
  'content_filter' => 'end_turn',
  // Legacy OpenAI.
  'function_call' => 'tool_use',
  _ => 'end_turn',
};

/// The reasoning text in a message or delta: `reasoning_content`, else
/// `reasoning`, else `reasoning_details`, as providers name it.
List<String> collectReasoningTexts(JsonValue object) {
  if (!object.exists) return const [];
  for (final path in const [
    'reasoning_content',
    'reasoning',
    'reasoning_details',
  ]) {
    final texts = _reasoningTexts(object.get(path));
    if (texts.isNotEmpty) return texts;
  }
  return const [];
}

List<String> _reasoningTexts(JsonValue node) {
  if (!node.exists) return const [];
  if (node.isArray) {
    return [for (final item in node.array) ..._reasoningTexts(item)];
  }
  if (node.isString) return [if (node.string.isNotEmpty) node.string];
  if (node.isObject) {
    final text = node.get('text');
    if (text.exists) return [if (text.string.isNotEmpty) text.string];
  }
  return const [];
}

/// The usage of an OpenAI reply: input tokens (less those read from or
/// written to the cache, which Anthropic counts apart), output tokens,
/// cache reads, cache writes.
(int, int, int, int) extractOpenAIUsage(JsonValue usage) {
  if (!usage.exists || usage.isNull) return (0, 0, 0, 0);
  var input = usage.get('prompt_tokens').integer;
  final output = usage.get('completion_tokens').integer;
  final cached = usage.get('prompt_tokens_details.cached_tokens').integer;
  var cacheWrite = usage
      .get('prompt_tokens_details.cache_write_tokens')
      .integer;
  if (cacheWrite <= 0) {
    cacheWrite = usage
        .get('prompt_tokens_details.cache_creation_tokens')
        .integer;
  }
  // One at a time, so that two huge counts cannot overflow.
  for (final deduct in [cached, cacheWrite]) {
    if (deduct > 0) input = input >= deduct ? input - deduct : 0;
  }
  return (input < 0 ? 0 : input, output, cached, cacheWrite);
}
