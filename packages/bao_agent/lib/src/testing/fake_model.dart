import 'dart:async';
import 'dart:convert';

import '../../bao_agent.dart';

/// What the model answers a request with: its content blocks, and why it
/// stopped.
class Reply {
  Reply(this.blocks, {this.stopReason, this.usage});

  /// Text.
  factory Reply.text(String text) => Reply([
    {'type': 'text', 'text': text},
  ]);

  /// A call of [name] with [input], after [text] if given.
  factory Reply.tool(
    String name,
    Map<String, Object?> input, {
    String? text,
    String? id,
  }) => Reply([
    if (text != null) {'type': 'text', 'text': text},
    {
      'type': 'tool_use',
      'id': id ?? 'toolu_${_next++}',
      'name': name,
      'input': input,
    },
  ], stopReason: 'tool_use');

  /// Several calls at once.
  factory Reply.tools(List<(String, Map<String, Object?>)> calls) => Reply([
    for (final (name, input) in calls)
      {
        'type': 'tool_use',
        'id': 'toolu_${_next++}',
        'name': name,
        'input': input,
      },
  ], stopReason: 'tool_use');

  static int _next = 1;

  final List<Map<String, Object?>> blocks;
  final String? stopReason;
  final Map<String, Object?>? usage;

  /// An error the API answers with instead.
  ApiError? error;

  static Reply failing(ApiError error) => Reply(const [])..error = error;
}

/// Answers a request; null to fall back to the script.
typedef Responder = Reply? Function(ModelRequest request);

/// A model under test: answers each request the agent makes with the next
/// reply of its script (its errands — titles, suggestions, checks — by
/// [errands]), streamed as the API streams.
class FakeModel implements ModelClient {
  FakeModel([List<Reply>? script, this.errands]) : script = script ?? [];

  final List<Reply> script;
  final Responder? errands;

  /// Every request, the agent's and its errands'.
  final List<ModelRequest> requests = [];

  /// The agent's own requests (not errands).
  List<ModelRequest> get turns => [
    for (final r in requests)
      if (!isErrand(r)) r,
  ];

  /// Whether [request] is one of the agent's errands: one with no tools,
  /// asked of a system prompt of its own.
  static bool isErrand(ModelRequest request) {
    final system = jsonEncode(request.body['system']);
    return request.body['tools'] == null &&
        !system.contains('summary of a conversation') &&
        !system.contains('interactive agent') &&
        !system.contains('You are an agent');
  }

  /// Answers the agent's own requests before the script does (a
  /// subagent's, say, running alongside); null to leave one to the script.
  Responder? route;

  /// Delays each streamed event (to interrupt a turn under test).
  Duration delay = Duration.zero;

  /// Whether it stands for Anthropic's own API (the requests laid out as
  /// for it), or for a provider's.
  @override
  bool firstParty = true;

  @override
  Future<List<Map<String, Object?>>?> models() async => null;

  @override
  Stream<Map<String, Object?>> stream(
    ModelRequest request, {
    CancelToken? cancel,
    void Function(RetryInfo info)? onRetry,
  }) async* {
    requests.add(request);
    Reply? reply;
    if (isErrand(request)) {
      reply = errands?.call(request) ?? Reply.text('');
    } else if (route?.call(request) case final routed?) {
      reply = routed;
    } else {
      if (script.isEmpty) {
        throw StateError(
          'The script has no reply for request ${requests.length}',
        );
      }
      reply = script.removeAt(0);
    }
    if (reply.error case final error?) throw error;
    final id = 'msg_${requests.length}';
    for (final event in replyEvents(reply, id: id, model: request.model)) {
      if (event['type'] == 'content_block_start' ||
          event['type'] == 'message_delta') {
        if (delay > Duration.zero) await Future<void>.delayed(delay);
        if (cancel?.isCancelled ?? false) throw const Cancelled('interrupted');
      }
      yield event;
    }
  }
}

/// The events the API streams for [reply], as message [id] of [model].
Iterable<Map<String, Object?>> replyEvents(
  Reply reply, {
  required String id,
  required String model,
}) sync* {
  yield {
    'type': 'message_start',
    'message': {
      'id': id,
      'type': 'message',
      'role': 'assistant',
      'model': model,
      'content': const [],
      'usage':
          reply.usage ??
          {
            'input_tokens': 100,
            'cache_creation_input_tokens': 0,
            'cache_read_input_tokens': 0,
            'output_tokens': 1,
          },
    },
  };
  for (final (index, block) in reply.blocks.indexed) {
    switch (block['type']) {
      case 'text':
        yield {
          'type': 'content_block_start',
          'index': index,
          'content_block': {'type': 'text', 'text': ''},
        };
        final text = '${block['text']}';
        for (var i = 0; i < text.length; i += 20) {
          yield {
            'type': 'content_block_delta',
            'index': index,
            'delta': {
              'type': 'text_delta',
              'text': text.substring(i, (i + 20).clamp(0, text.length)),
            },
          };
        }
      case 'thinking':
        yield {
          'type': 'content_block_start',
          'index': index,
          'content_block': {'type': 'thinking', 'thinking': ''},
        };
        yield {
          'type': 'content_block_delta',
          'index': index,
          'delta': {'type': 'thinking_delta', 'thinking': block['thinking']},
        };
        yield {
          'type': 'content_block_delta',
          'index': index,
          'delta': {'type': 'signature_delta', 'signature': 'sig'},
        };
      case 'tool_use':
        yield {
          'type': 'content_block_start',
          'index': index,
          'content_block': {
            'type': 'tool_use',
            'id': block['id'],
            'name': block['name'],
            'input': const <String, Object?>{},
          },
        };
        final json = jsonEncode(block['input']);
        for (var i = 0; i < json.length; i += 30) {
          yield {
            'type': 'content_block_delta',
            'index': index,
            'delta': {
              'type': 'input_json_delta',
              'partial_json': json.substring(i, (i + 30).clamp(0, json.length)),
            },
          };
        }
      default:
        // Whole, as the API sends the server's own blocks.
        yield {
          'type': 'content_block_start',
          'index': index,
          'content_block': block,
        };
    }
    yield {'type': 'content_block_stop', 'index': index};
  }
  yield {
    'type': 'message_delta',
    'delta': {'stop_reason': reply.stopReason ?? 'end_turn'},
    'usage': {'output_tokens': 20},
  };
  yield {'type': 'message_stop'};
}
