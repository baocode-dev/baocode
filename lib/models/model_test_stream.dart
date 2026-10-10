import 'dart:convert';

import 'model_provider.dart';
import 'model_test.dart';

/// One parser per native SSE stream. Heartbeats/role/usage never count as
/// first text. Completion must come from the upstream, not from socket EOF.
class ModelTestStreamParser {
  ModelTestStreamParser(this.protocol);
  final ProviderProtocol protocol;
  final _data = <String>[];
  int _frameSize = 0;
  bool _done = false;

  ModelTestEvent? addLine(String line) {
    if (line.isEmpty) {
      if (_data.isEmpty) return null;
      final data = _data.join('\n');
      _data.clear();
      _frameSize = 0;
      return _decode(data);
    }
    if (line.startsWith('data:')) {
      final data = line.substring(5).trimLeft();
      _frameSize += data.length;
      if (_frameSize > 1048576) {
        throw const FormatException('SSE frame too large');
      }
      _data.add(data);
    }
    return null;
  }

  ModelTestEvent? finish() => addLine('');

  ModelTestEvent? _decode(String data) {
    if (data.trim() == '[DONE]') {
      if (protocol != ProviderProtocol.openaiChat) return null;
      _done = true;
      return const ModelTestEvent(done: true);
    }
    final json = jsonDecode(data);
    if (json is! Map) throw const FormatException('Invalid SSE event');
    if (json['error'] != null ||
        json['type'] == 'error' ||
        json['type'] == 'response.failed' ||
        json['type'] == 'response.incomplete') {
      throw FormatException(jsonEncode(json));
    }
    if (protocol == ProviderProtocol.openaiChat) {
      final usage = json['usage'];
      var text = '';
      var thinking = '';
      if (json['choices'] case final List choices when choices.isNotEmpty) {
        final choice = choices.first;
        if (choice is Map) {
          if (choice['finish_reason'] != null &&
              choice['finish_reason'] != 'stop') {
            throw FormatException(
              'Generation stopped: ${choice['finish_reason']}',
            );
          }
          if (choice['delta'] case final Map delta) {
            text = _text(delta['content']);
            thinking = _text(delta['reasoning_content'] ?? delta['reasoning']);
          }
        }
      }
      return ModelTestEvent(
        text: text,
        thinking: thinking,
        inputTokens: _tokens(usage, 'prompt_tokens'),
        outputTokens: _tokens(usage, 'completion_tokens'),
      );
    }
    if (protocol == ProviderProtocol.anthropic) {
      final type = json['type'];
      var text = '';
      var thinking = '';
      if (type == 'content_block_delta' && json['delta'] is Map) {
        final delta = json['delta'] as Map;
        if (delta['type'] == 'text_delta') text = _text(delta['text']);
        if (delta['type'] == 'thinking_delta') {
          thinking = _text(delta['thinking']);
        }
      }
      if (type == 'content_block_start' && json['content_block'] is Map) {
        final block = json['content_block'] as Map;
        if (block['type'] == 'text') text = _text(block['text']);
      }
      if (type == 'message_delta' && json['delta'] is Map) {
        final stop = (json['delta'] as Map)['stop_reason'];
        if (stop != null && stop != 'end_turn' && stop != 'stop_sequence') {
          throw FormatException('Generation stopped: $stop');
        }
      }
      final message = json['message'];
      final usage = json['usage'] ?? (message is Map ? message['usage'] : null);
      if (type == 'message_stop') _done = true;
      return ModelTestEvent(
        text: text,
        thinking: thinking,
        inputTokens: _tokens(usage, 'input_tokens'),
        outputTokens: _tokens(usage, 'output_tokens'),
        done: type == 'message_stop',
      );
    }
    final type = json['type'];
    final response = json['response'];
    final usage = response is Map ? response['usage'] : null;
    if (type == 'response.completed') {
      if (response is Map &&
          response['status'] != null &&
          response['status'] != 'completed') {
        throw const FormatException('Response did not complete');
      }
      _done = true;
    }
    return ModelTestEvent(
      text: type == 'response.output_text.delta' ? _text(json['delta']) : '',
      thinking:
          type == 'response.reasoning_summary_text.delta' ||
              type == 'response.reasoning_text.delta'
          ? _text(json['delta'])
          : '',
      inputTokens: _tokens(usage, 'input_tokens'),
      outputTokens: _tokens(usage, 'output_tokens'),
      done: type == 'response.completed',
    );
  }

  bool get done => _done;
  static String _text(Object? value) => value is String ? value : '';
  static int? _tokens(Object? usage, String key) =>
      usage is Map && usage[key] is int && (usage[key] as int) >= 0
      ? usage[key] as int
      : null;
}

/// Only explicitly offered reasoning levels are sent. Unknown/generic models
/// receive no reasoning or temperature field: unsupported parameters can make
/// a connectivity test fail before generation even starts.
Map<String, Object?> modelTestRequest(
  ModelProvider provider,
  ProviderModel model,
  String prompt,
) {
  final disableReasoning = model.efforts?.contains('none') == true;
  return switch (provider.protocol) {
    ProviderProtocol.anthropic => {
      'model': model.id,
      'stream': true,
      'max_tokens': 2048,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
    },
    ProviderProtocol.openaiChat => {
      'model': model.id,
      'stream': true,
      'stream_options': {'include_usage': true},
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
      if (disableReasoning) 'reasoning_effort': 'none',
    },
    ProviderProtocol.openaiResponses || ProviderProtocol.codex => {
      'model': model.id,
      'stream': true,
      'store': false,
      'input': [
        {'role': 'user', 'content': prompt},
      ],
      if (disableReasoning) 'reasoning': {'effort': 'none'},
    },
  };
}
