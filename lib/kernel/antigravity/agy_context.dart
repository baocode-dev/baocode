import 'dart:convert';
import 'dart:math' as math;

import 'package:bao_agent/bao_agent.dart' show ForeignBrief;

/// What fills an Antigravity session's context, as `get_context_usage`
/// answers it (Claude Code's shape), estimated: agy tells only how much is
/// used of how much ([used], [size]; ACP's `usage_update`).
///
/// What BaoCode told it is estimated from what it told: the instructions
/// and skills ([brief]), the conversation agy holds (in [chain]: its own
/// turns, `msg_agy_…` and `toolu_agy_…`, and the prompts they answer), and
/// what was [handedOff] of turns on other models. The rest of [used] is
/// agy's own prompt and tools. Where the estimates come to more than
/// [used] (agy compacted its context), the conversation's are scaled down
/// into what is left.
Map<String, Object?> agyContextUsage({
  required int used,
  required int size,
  ForeignBrief brief = const ForeignBrief(),
  List<Map<String, Object?>> chain = const [],
  int handedOff = 0,
}) {
  final files = [
    for (final file in brief.files)
      {'path': file.path, 'type': file.type, 'tokens': agyTokens(file.text)},
  ];
  final skills = [
    for (final skill in brief.skills)
      {'name': skill.name, 'tokens': agyTokens(skill.text), 'source': 'user'},
  ];
  int sum(List<Map<String, Object?>> items) =>
      items.fold(0, (total, item) => total + (item['tokens'] as int));
  final memory = math.min(sum(files), used);
  final skillTokens = math.min(sum(skills), used - memory);

  // The conversation as agy holds it.
  var user = handedOff;
  var assistant = 0;
  final calls = <String, int>{};
  final results = <String, int>{};
  final names = <String, String>{};
  for (var i = 0; i < chain.length; i++) {
    final entry = chain[i];
    final message = entry['message'];
    if (message is! Map) continue;
    final content = message['content'];
    switch (entry['type']) {
      case 'assistant' when _ofAgy(message):
        for (final block in content is List ? content : const []) {
          if (block is! Map) continue;
          switch (block['type']) {
            case 'text':
              assistant += agyTokens('${block['text'] ?? ''}');
            case 'tool_use':
              final name = '${block['name'] ?? 'Tool'}';
              names['${block['id']}'] = name;
              calls[name] =
                  (calls[name] ?? 0) +
                  agyTokens(name) +
                  agyTokens(jsonEncode(block['input'] ?? const {}));
          }
        }
      case 'user':
        if (content is String) {
          if (_answeredByAgy(chain, i)) user += agyTokens(content);
          continue;
        }
        var prompt = 0;
        for (final block in content is List ? content : const []) {
          if (block is! Map) continue;
          switch (block['type']) {
            case 'tool_result'
                when '${block['tool_use_id']}'.startsWith('toolu_agy_'):
              final name = names['${block['tool_use_id']}'] ?? 'Tool';
              results[name] =
                  (results[name] ?? 0) + agyTokens(_text(block['content']));
            case 'text':
              prompt += agyTokens('${block['text'] ?? ''}');
            case 'image':
              prompt += 1600;
          }
        }
        if (prompt > 0 && _answeredByAgy(chain, i)) user += prompt;
    }
  }
  int total(Map<String, int> tokens) =>
      tokens.values.fold(0, (sum, value) => sum + value);
  final estimated = user + assistant + total(calls) + total(results);
  final room = math.max(used - memory - skillTokens, 0);
  final scale = estimated > room && estimated > 0 ? room / estimated : 1.0;
  int scaled(int tokens) => (tokens * scale).round();
  final messages = math.min(scaled(estimated), room);
  final system = room - messages;
  final tools = {...calls.keys, ...results.keys};
  return {
    'categories': [
      if (used > 0) ...[
        {'name': 'System prompt', 'tokens': system, 'kind': 'used'},
        if (memory > 0)
          {'name': 'Memory files', 'tokens': memory, 'kind': 'used'},
        if (skillTokens > 0)
          {'name': 'Skills', 'tokens': skillTokens, 'kind': 'used'},
        {'name': 'Messages', 'tokens': messages, 'kind': 'used'},
      ],
      if (size > used)
        {'name': 'Free space', 'tokens': size - used, 'kind': 'free'},
    ],
    'totalTokens': used,
    'maxTokens': size,
    'rawMaxTokens': size,
    'percentage': size == 0 ? 0 : (used * 100 / size).round(),
    'memoryFiles': files,
    'skills': {'skillFrontmatter': skills},
    'messageBreakdown': {
      'userMessageTokens': scaled(user),
      'assistantMessageTokens': scaled(assistant),
      'toolCallTokens': scaled(total(calls)),
      'toolResultTokens': scaled(total(results)),
      'toolCallsByType': [
        for (final name in tools)
          {
            'name': name,
            'callTokens': scaled(calls[name] ?? 0),
            'resultTokens': scaled(results[name] ?? 0),
          },
      ],
    },
    // agy compacts by itself, where BaoCode is not told.
    'isAutoCompactEnabled': false,
  };
}

/// Tokens [text] is likely to be to Gemini's tokenizer: about four ASCII
/// characters each, about one for each other (Han, mostly).
int agyTokens(String text) {
  var ascii = 0;
  var other = 0;
  for (final rune in text.runes) {
    rune < 0x80 ? ascii++ : other++;
  }
  return (ascii / 4 + other).round();
}

bool _ofAgy(Map<Object?, Object?> message) =>
    '${message['id'] ?? ''}'.startsWith('msg_agy_');

/// Whether the prompt at [index] was agy's to answer: the answer after it
/// is agy's.
bool _answeredByAgy(List<Map<String, Object?>> chain, int index) {
  for (var i = index + 1; i < chain.length; i++) {
    if (chain[i] case {'type': 'assistant', 'message': final Map message}) {
      return _ofAgy(message);
    }
  }
  return false;
}

String _text(Object? content) => switch (content) {
  final String text => text,
  final List<Object?> blocks => [
    for (final block in blocks)
      if (block case {'type': 'text', 'text': final String text}) text,
  ].join('\n'),
  _ => '',
};
