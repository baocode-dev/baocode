// After magpie's internal/gateway/codeassist.go (buildCodeAssistSent,
// pairFunctionTurns, dropSecondAnswers, thinkingConfig) and CLIProxyAPI's
// internal/translator/antigravity/claude/antigravity_claude_request.go (MIT
// License; see NOTICE.md beside this file).

import 'dart:convert';

import '../../antigravity/antigravity_api.dart';
import 'antigravity_cloak.dart';
import 'antigravity_schema.dart';
import 'antigravity_signature.dart';

/// What Gemini takes back in place of a signature for history it did not
/// sign.
const skipThoughtSignature = 'skip_thought_signature_validator';

/// The answer a call left unanswered is given.
const _interrupted =
    '[The result of this tool call is unavailable: the turn was interrupted.]';

/// Stands before a function name Google would refuse (one starting with a
/// digit, a dash, a dot or a colon); taken off its calls' names again.
const antigravityNameLead = '_x_';

/// A tool's name as Google takes it.
String antigravityFunctionName(String name) {
  if (name.isEmpty) return name;
  final first = name.codeUnitAt(0);
  final bad =
      (first >= 0x30 && first <= 0x39) ||
      first == 0x2d ||
      first == 0x2e ||
      first == 0x3a;
  return bad ? '$antigravityNameLead$name' : name;
}

/// A call's tool name as the request named it: without Gemini's namespace
/// (`default_api:`) or [antigravityNameLead].
String antigravityToolOfCall(String name) {
  for (final separator in const [':', '.']) {
    final prefix = 'default_api$separator';
    if (name.startsWith(prefix) && name.length > prefix.length) {
      name = name.substring(prefix.length);
      break;
    }
  }
  return name.startsWith(antigravityNameLead)
      ? name.substring(antigravityNameLead.length)
      : name;
}

final _unsafeId = RegExp(r'[^a-zA-Z0-9_-]');

/// Whether [type] is one of Anthropic's built-in web search tool types.
bool isAntigravityWebSearchToolType(String type) =>
    type == 'web_search_20250305' || type == 'web_search_20260209';

/// Whether [model] runs Google Search natively on Antigravity: Gemini text
/// models, not Claude, GPT-OSS or image-generation models.
bool antigravitySupportsWebSearch(String model) {
  final lower = model.toLowerCase();
  return lower.contains('gemini') &&
      !lower.contains('image') &&
      !lower.contains('imagen');
}

/// Whether [body] asks only for Anthropic's built-in `web_search` tool (no
/// function tools beside it) and does not forbid tools.
bool antigravityHasOnlyWebSearch(Map<String, Object?> body) {
  final choice = body['tool_choice'] is Map ? body['tool_choice'] as Map : null;
  if (choice?['type'] == 'none') return false;
  final tools = body['tools'];
  if (tools is! List || tools.isEmpty) return false;
  var hasWebSearch = false;
  for (final tool in tools) {
    if (tool is! Map) continue;
    if (isAntigravityWebSearchToolType('${tool['type'] ?? ''}')) {
      hasWebSearch = true;
    } else if (tool['name'] is String && tool.containsKey('input_schema')) {
      return false;
    }
  }
  return hasWebSearch;
}

/// The latest user text in [body], used as the query shown in a synthesized
/// web search tool call.
String antigravityWebSearchQuery(Map<String, Object?> body) {
  final messages = _messages(body);
  for (var i = messages.length - 1; i >= 0; i--) {
    if (messages[i]['role'] != 'user') continue;
    final parts = [
      for (final block in _blocks(messages[i]['content']))
        if (block['type'] == 'text')
          if ('${block['text'] ?? ''}'.trim() case final text
              when text.isNotEmpty)
            text,
    ];
    if (parts.isNotEmpty) return parts.join('\n');
  }
  return '';
}

/// An Anthropic Messages request ([body]) as Code Assist's `request`, for
/// model [model] (the id it goes out as) at [effort]: its system prompt
/// and turns as Gemini's, its tools' schemas cut to what Antigravity
/// takes, the lines it turns away reworded ([antigravityCloak]). The
/// signatures [store] keeps go back on the calls whose ids carry them.
Map<String, Object?> convertClaudeRequestToAntigravity(
  Map<String, Object?> body, {
  required String model,
  String? effort,
  SignatureStore? store,
}) {
  final claude = model.toLowerCase().contains('claude');
  final names = <String, String>{};
  final contents = <Map<String, Object?>>[];

  for (final message in _dropSecondAnswers(_messages(body))) {
    final role = message['role'] == 'assistant' ? 'model' : 'user';
    final blocks = _blocks(message['content']);
    var parts = <Map<String, Object?>>[];
    final after = <Map<String, Object?>>[];
    final toolImage = <int>{};
    // A step Gemini signed: its later calls go without, as Gemini signs
    // the first.
    final signed = blocks.any(
      (b) =>
          b['type'] == 'tool_use' &&
          unsignedToolId('${b['id'] ?? ''}', store).$2 != null,
    );
    for (final block in blocks) {
      switch (block['type']) {
        case 'text':
          var text = '${block['text'] ?? ''}';
          if (role == 'user') text = antigravityCloakUserText(text);
          if (text.isNotEmpty) parts.add({'text': text});
        case 'image' || 'document':
          if (_inline(block['source']) case final part?) parts.add(part);
        case 'tool_use':
          final rawId = '${block['id'] ?? ''}';
          final name = '${block['name'] ?? ''}';
          names[rawId] = name;
          final (id, signature) = unsignedToolId(rawId, store);
          final call = <String, Object?>{
            'name': antigravityFunctionName(name),
            'args': block['input'] is Map
                ? block['input']
                : <String, Object?>{},
            if (id.isNotEmpty) 'id': id.replaceAll(_unsafeId, '_'),
          };
          final part = <String, Object?>{'functionCall': call};
          if (claude) {
            part['thoughtSignature'] = skipThoughtSignature;
          } else if (signature != null) {
            part['thoughtSignature'] = signature;
          } else if (!signed) {
            part['thoughtSignature'] = skipThoughtSignature;
          }
          parts.add(part);
        case 'tool_result':
          final rawId = '${block['tool_use_id'] ?? ''}';
          var name = antigravityFunctionName(names[rawId] ?? '');
          if (name.isEmpty) name = 'tool';
          final (id, _) = unsignedToolId(rawId, store);
          final safeId = id.replaceAll(_unsafeId, '_');
          final (text, images) = _toolResult(block['content']);
          parts.add({
            'functionResponse': {
              'name': name,
              if (safeId.isNotEmpty) 'id': safeId,
              'response': {
                'result': block['is_error'] == true && text.isNotEmpty
                    ? 'Error: $text'
                    : text,
              },
            },
          });
          if (claude && images.isNotEmpty) {
            // Antigravity hands Claude the turn as Anthropic blocks, where
            // an image between two results splits them from their calls:
            // the images wait until every result is in, each said whose.
            after
              ..add({
                'text': images.length == 1
                    ? 'Image returned by tool $name (call $safeId):'
                    : '${images.length} images returned by tool $name '
                          '(call $safeId):',
              })
              ..addAll(images);
          } else {
            for (final image in images) {
              toolImage.add(parts.length);
              parts.add(image);
            }
          }
        // Thinking is not sent back: its signatures are whoever's made
        // them, and Google refuses those it did not.
      }
    }
    if (after.isNotEmpty) {
      parts = [
        ...parts.where((p) => p.containsKey('functionResponse')),
        ...after,
        ...parts.where((p) => !p.containsKey('functionResponse')),
      ];
    }
    // What the user said goes in a turn of its own after the tools'
    // results: Gemini refuses a turn mixing them. Claude on Antigravity
    // keeps them in one, the tool_result turn Anthropic reads.
    var said = <Map<String, Object?>>[];
    if (role == 'user' && !claude && _hasResponse(parts)) {
      final tools = <Map<String, Object?>>[];
      for (final (i, part) in parts.indexed) {
        if (part.containsKey('functionResponse') || toolImage.contains(i)) {
          tools.add(part);
        } else {
          said.add(part);
        }
      }
      parts = tools;
    }
    for (final group in [parts, said]) {
      if (group.isEmpty) continue;
      final last = contents.lastOrNull;
      if (last != null &&
          last['role'] == role &&
          (role != 'user' ||
              _hasResponse(last['parts'] as List) == _hasResponse(group))) {
        (last['parts'] as List).addAll(group);
        continue;
      }
      contents.add({'role': role, 'parts': group});
    }
  }
  final paired = _pairFunctionTurns(contents, claude);
  if (paired.isNotEmpty && paired.first['role'] == 'model') {
    // Gemini refuses a history that opens with the model's turn.
    paired.insert(0, {
      'role': 'user',
      'parts': [
        {'text': '[Continuing from previous AI thoughts...]'},
      ],
    });
  }
  if (paired.isNotEmpty && paired.last['role'] == 'model') {
    // Nor one that ends with it.
    paired.add({
      'role': 'user',
      'parts': [
        {'text': 'Continue.'},
      ],
    });
  }

  final request = <String, Object?>{'contents': paired};
  final systemParts = <String>[];
  final system = antigravityCloak(_systemText(body['system']));
  if (system.isNotEmpty) systemParts.add(system);

  final choice = body['tool_choice'] is Map ? body['tool_choice'] as Map : null;
  final declarations = <Map<String, Object?>>[];
  Map? webSearch;
  for (final tool in (body['tools'] as List?) ?? const []) {
    if (tool is! Map) continue;
    if (isAntigravityWebSearchToolType('${tool['type'] ?? ''}')) {
      webSearch ??= tool;
      continue;
    }
    if (tool['name'] is String && tool.containsKey('input_schema')) {
      declarations.add({
        'name': antigravityFunctionName(tool['name'] as String),
        if (tool['description'] case final String d when d.isNotEmpty)
          'description': d,
        'parameters': antigravitySchema(tool['input_schema']),
      });
    }
  }
  if (declarations.isNotEmpty && choice?['type'] != 'none') {
    request['tools'] = [
      {'functionDeclarations': declarations},
    ];
    final calling = <String, Object?>{};
    switch (choice?['type']) {
      case 'any':
        calling['mode'] = 'ANY';
      case 'tool':
        calling['mode'] = 'ANY';
        calling['allowedFunctionNames'] = [
          antigravityFunctionName('${choice?['name'] ?? ''}'),
        ];
      default:
        // Antigravity's Claude wants its calls checked against the schema.
        calling['mode'] = claude ? 'VALIDATED' : 'AUTO';
    }
    request['toolConfig'] = {'functionCallingConfig': calling};
  } else if (webSearch != null &&
      choice?['type'] != 'none' &&
      antigravitySupportsWebSearch(model)) {
    // Code Assist runs Google Search natively on Gemini as long as no
    // function declarations are sent alongside it.
    request['tools'] = [
      {'googleSearch': <String, Object?>{}},
    ];
    final allowed = _domainList(webSearch['allowed_domains']);
    if (allowed.isNotEmpty) {
      systemParts.add(
        'Restrict web search results to these domains: ${allowed.join(', ')}.',
      );
    }
    final blocked = _domainList(webSearch['blocked_domains']);
    if (blocked.isNotEmpty) {
      systemParts.add(
        'Exclude web search results from these domains: ${blocked.join(', ')}.',
      );
    }
  }
  if (systemParts.isNotEmpty) {
    request['systemInstruction'] = {
      'role': 'user',
      'parts': [
        {'text': systemParts.join('\n\n')},
      ],
    };
  }

  final generation = <String, Object?>{};
  final maxTokens = switch (body['max_tokens']) {
    final num n when n > 0 => n.toInt(),
    _ => null,
  };
  // As Antigravity's own app asks: only Claude's output capped.
  if (claude && maxTokens != null) generation['maxOutputTokens'] = maxTokens;
  if (body['temperature'] case final num t) generation['temperature'] = t;
  if (body['top_p'] case final num p) generation['topP'] = p;
  if (body['top_k'] case final num k) generation['topK'] = k;
  if (body['stop_sequences'] case final List stops when stops.isNotEmpty) {
    generation['stopSequences'] = stops;
  }
  final thinking = antigravityThinking(
    model,
    effort: effort,
    budget: switch (body['thinking']) {
      {'type': 'enabled', 'budget_tokens': final num budget} => budget.toInt(),
      _ => null,
    },
    maxTokens: maxTokens,
  );
  if (thinking != null) {
    generation['thinkingConfig'] = thinking;
    if (thinking['thinkingBudget'] case final int budget
        when claude && generation['maxOutputTokens'] == null) {
      generation['maxOutputTokens'] = budget + 32000;
    }
  }
  if (generation.isNotEmpty) request['generationConfig'] = generation;
  return request;
}

/// How hard [model] thinks: a level for Gemini 3 and later (the one its id
/// says, for a variant at one), a budget for the rest; none for a model
/// that does not think, nor without [effort] (or a [budget]) for one whose
/// id says no level.
Map<String, Object?>? antigravityThinking(
  String model, {
  String? effort,
  int? budget,
  int? maxTokens,
}) {
  final lower = model.toLowerCase();
  final claude = lower.contains('claude');
  if (lower.startsWith('gpt-oss') || claude && !lower.contains('thinking')) {
    return null;
  }
  final (_, at) = splitAntigravityId(lower);
  final asked = effort != null && effort.isNotEmpty;
  final generation = geminiGeneration(lower);
  if (generation >= 3) {
    final level = at ?? (asked ? effort : null);
    if (level == null) return null;
    final flash = lower.contains('flash');
    final String thinkingLevel;
    if (at == 'xhigh') {
      thinkingLevel = 'xhigh';
    } else if (level == 'low' || level == 'minimal' && at != null && !flash) {
      thinkingLevel = 'low';
    } else if (level == 'minimal' && at != null) {
      thinkingLevel = 'minimal';
    } else if (level == 'none' || level == 'minimal') {
      thinkingLevel = 'low';
    } else if (level == 'medium' && (flash || generation > 3)) {
      thinkingLevel = 'medium';
    } else {
      thinkingLevel = 'high';
    }
    return {'includeThoughts': true, 'thinkingLevel': thinkingLevel};
  }
  if (!asked && budget == null && !claude) return null;
  if (effort == 'none' && !claude) {
    return {'thinkingBudget': lower.contains('pro') ? 128 : 0};
  }
  var tokens =
      budget ??
      switch (effort) {
        'minimal' || 'low' => 4096,
        'medium' => 8192,
        'high' => 24576,
        'xhigh' || 'max' => 32768,
        _ => 8192,
      };
  if (claude && maxTokens != null && tokens >= maxTokens) {
    tokens = maxTokens - 1;
    if (tokens < 1024) return null;
  }
  return {'includeThoughts': true, 'thinkingBudget': tokens};
}

List<Map<String, Object?>> _messages(Map<String, Object?> body) => [
  for (final message in (body['messages'] as List?) ?? const [])
    if (message is Map<String, Object?>) message,
];

List<Map<String, Object?>> _blocks(Object? content) => switch (content) {
  final String text => [
    {'type': 'text', 'text': text},
  ],
  final List blocks => [
    for (final block in blocks)
      if (block is Map<String, Object?>) block,
  ],
  _ => const [],
};

/// A result whose call an earlier result already answered is left out:
/// Google refuses a turn whose results do not match its calls one for one.
List<Map<String, Object?>> _dropSecondAnswers(
  List<Map<String, Object?>> messages,
) {
  final answered = <String>{};
  final out = <Map<String, Object?>>[];
  for (final message in messages) {
    final content = message['content'];
    if (content is! List) {
      out.add(message);
      continue;
    }
    final kept = <Object?>[];
    for (final block in content) {
      if (block is Map && block['type'] == 'tool_use') {
        answered.remove('${block['id'] ?? ''}');
      } else if (block is Map && block['type'] == 'tool_result') {
        final id = '${block['tool_use_id'] ?? ''}';
        if (id.isNotEmpty && !answered.add(id)) continue;
      }
      kept.add(block);
    }
    if (kept.isEmpty && content.isNotEmpty) continue;
    out.add({...message, 'content': kept});
  }
  return out;
}

/// Each model turn's calls answered in the turn after it: a call answered
/// nowhere (an interrupted turn's) is answered as interrupted, else Google
/// refuses every later turn.
List<Map<String, Object?>> _pairFunctionTurns(
  List<Map<String, Object?>> contents,
  bool claude,
) {
  final answered = <String>{};
  final answeredNames = <String>{};
  for (final content in contents) {
    for (final part in content['parts'] as List) {
      if (part case {'functionResponse': final Map response}) {
        final id = '${response['id'] ?? ''}';
        if (id.isNotEmpty) {
          answered.add(id);
        } else {
          answeredNames.add('${response['name'] ?? ''}');
        }
      }
    }
  }
  final out = <Map<String, Object?>>[];
  for (final (i, content) in contents.indexed) {
    out.add(content);
    if (content['role'] != 'model') continue;
    final synthetic = <Map<String, Object?>>[];
    for (final part in content['parts'] as List) {
      if (part case {'functionCall': final Map call}) {
        final id = '${call['id'] ?? ''}';
        final name = '${call['name'] ?? ''}';
        if (id.isNotEmpty
            ? answered.contains(id)
            : answeredNames.contains(name)) {
          continue;
        }
        synthetic.add({
          'functionResponse': {
            'name': name,
            if (id.isNotEmpty) 'id': id,
            'response': {'result': _interrupted},
          },
        });
      }
    }
    if (synthetic.isEmpty) continue;
    final next = i + 1 < contents.length ? contents[i + 1] : null;
    if (next != null &&
        next['role'] == 'user' &&
        (claude || _hasResponse(next['parts'] as List))) {
      (next['parts'] as List).insertAll(0, synthetic);
      continue;
    }
    out.add({'role': 'user', 'parts': synthetic});
  }
  return out;
}

bool _hasResponse(List parts) =>
    parts.any((part) => part is Map && part.containsKey('functionResponse'));

/// An image or a document as Gemini's part: inline data; a URL as a file.
Map<String, Object?>? _inline(Object? source) => switch (source) {
  {'type': 'base64', 'data': final String data} when data.isNotEmpty => {
    'inlineData': {
      'mimeType': '${source['media_type'] ?? 'image/png'}',
      'data': data,
    },
  },
  {'type': 'url', 'url': final String url} when url.isNotEmpty => {
    'fileData': {'mimeType': _mimeOf(url), 'fileUri': url},
  },
  {'type': 'text', 'data': final String text} when text.isNotEmpty => {
    'text': text,
  },
  _ => null,
};

String _mimeOf(String url) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
  if (path.endsWith('.png')) return 'image/png';
  if (path.endsWith('.gif')) return 'image/gif';
  if (path.endsWith('.webp')) return 'image/webp';
  if (path.endsWith('.pdf')) return 'application/pdf';
  return 'image/jpeg';
}

/// A tool result's text, and its images as parts.
(String, List<Map<String, Object?>>) _toolResult(Object? content) {
  if (content is String) return (content, const []);
  if (content is! List) return ('', const []);
  final text = <String>[];
  final images = <Map<String, Object?>>[];
  for (final block in content) {
    if (block is! Map) continue;
    switch (block['type']) {
      case 'text':
        text.add('${block['text'] ?? ''}');
      case 'image' || 'document':
        if (_inline(block['source']) case final part?) {
          if (part.containsKey('text')) {
            text.add('${part['text']}');
          } else {
            images.add(part);
          }
        }
      default:
        text.add(jsonEncode(block));
    }
  }
  return (text.join('\n'), images);
}

/// The system prompt's text, its blocks one after another.
String _systemText(Object? system) => switch (system) {
  final String text => text,
  final List blocks => [
    for (final block in blocks)
      if (block is Map && block['type'] == 'text')
        if (block['text'] case final String text when text.isNotEmpty) text,
  ].join('\n'),
  _ => '',
};

List<String> _domainList(Object? value) => [
  if (value is List)
    for (final item in value)
      if (item is String && item.trim().isNotEmpty) item.trim(),
];

/// The text a conversation is known by over its turns: its first user
/// text, for [antigravitySessionId]'s seed.
String antigravityFirstUserText(Map<String, Object?> body) {
  for (final message in _messages(body)) {
    if (message['role'] != 'user') continue;
    for (final block in _blocks(message['content'])) {
      if (block['type'] == 'text') {
        final text = '${block['text'] ?? ''}';
        if (text.isNotEmpty) return text;
      }
    }
    break;
  }
  return '';
}
