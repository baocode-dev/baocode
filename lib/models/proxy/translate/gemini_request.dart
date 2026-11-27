import 'dart:convert';

import '../../antigravity/antigravity_api.dart';
import '../../image_api.dart';
import 'antigravity_request.dart';
import 'antigravity_signature.dart';

/// The answer an interrupted tool call is given so later turns still pair.
const _interrupted =
    '[The result of this tool call is unavailable: the turn was interrupted.]';

/// Image MIME types Gemini's `inlineData` accepts natively.
const _geminiImageTypes = {
  'image/png',
  'image/jpeg',
  'image/webp',
  'image/heic',
  'image/heif',
};

/// An Anthropic Messages request ([body]) as a standard Gemini API
/// `generateContent` / `streamGenerateContent` request body, for [model] at
/// [effort].
///
/// Unlike Code Assist, the request goes without a wrapper envelope, without
/// `model`, `stream`, or `sessionId` fields, without system-prompt cloaking,
/// and with full JSON Schemas under `parametersJsonSchema`. Thought signatures
/// kept in [store] are restored onto their function calls.
Map<String, Object?> convertClaudeRequestToGemini(
  Map<String, Object?> body, {
  required String model,
  String? effort,
  SignatureStore? store,
}) {
  final names = <String, String>{};
  final contents = <Map<String, Object?>>[];

  for (final message in _dropSecondAnswers(_messages(body))) {
    final role = message['role'] == 'assistant' ? 'model' : 'user';
    final blocks = _blocks(message['content']);
    var parts = <Map<String, Object?>>[];
    final after = <Map<String, Object?>>[];
    final signed = blocks.any(
      (b) =>
          b['type'] == 'tool_use' &&
          unsignedToolId('${b['id'] ?? ''}', store).$2 != null,
    );

    for (final block in blocks) {
      switch (block['type']) {
        case 'text':
          final text = '${block['text'] ?? ''}';
          if (text.isNotEmpty) parts.add({'text': text});
        case 'image' || 'document':
          if (_inlinePart(block['source']) case final part?) {
            parts.add(part);
          }
        case 'tool_use':
          final rawId = '${block['id'] ?? ''}';
          final name = '${block['name'] ?? ''}';
          if (rawId.isNotEmpty) names[rawId] = name;
          final (id, signature) = unsignedToolId(rawId, store);
          final input = block['input'];
          parts.add({
            'functionCall': {
              'name': antigravityFunctionName(name),
              'args': input is Map ? input : const <String, Object?>{},
              if (id.isNotEmpty) 'id': id,
            },
            if (signature != null)
              'thoughtSignature': signature
            else if (!signed)
              'thoughtSignature': skipThoughtSignature,
          });
        case 'tool_result':
          final rawId = '${block['tool_use_id'] ?? ''}';
          final (id, _) = unsignedToolId(rawId, store);
          final name = antigravityFunctionName(names[rawId] ?? '');
          final (text, media) = _toolResult(block['content']);
          parts.add({
            'functionResponse': {
              'name': name.isEmpty ? 'tool' : name,
              if (id.isNotEmpty) 'id': id,
              'response': {
                block['is_error'] == true ? 'error' : 'output': text,
              },
            },
          });
          parts.addAll(media);
        case 'thinking':
          // Cross-model or unsigned thinking blocks are rejected by Gemini.
          break;
      }
    }

    // Gemini refuses user text in the same turn as functionResponse parts:
    // keep functionResponses (and their media) in their own user turn, and
    // move trailing user text to a following user turn.
    if (role == 'user' && parts.any((p) => p.containsKey('functionResponse'))) {
      final responses = <Map<String, Object?>>[];
      for (final part in parts) {
        if (part.containsKey('text')) {
          after.add(part);
        } else {
          responses.add(part);
        }
      }
      parts = responses;
    }

    if (parts.isNotEmpty) _appendTurn(contents, role, parts);
    if (after.isNotEmpty) _appendTurn(contents, 'user', after);
  }

  final paired = _pairFunctionTurns(contents);
  if (paired.isNotEmpty && paired.first['role'] == 'model') {
    paired.insert(0, {
      'role': 'user',
      'parts': [
        {'text': '[Continuing from previous AI thoughts...]'},
      ],
    });
  }
  if (paired.isNotEmpty && paired.last['role'] == 'model') {
    paired.add({
      'role': 'user',
      'parts': [
        {'text': 'Continue.'},
      ],
    });
  }

  final request = <String, Object?>{'contents': paired};
  final systemParts = <String>[];
  final system = _systemText(body['system']);
  if (system.isNotEmpty) systemParts.add(system);

  final declarations = <Map<String, Object?>>[];
  Map<String, Object?>? webSearch;
  for (final tool in (body['tools'] as List?) ?? const []) {
    if (tool is! Map) continue;
    final type = '${tool['type'] ?? ''}';
    if (isAntigravityWebSearchToolType(type)) {
      webSearch ??= Map<String, Object?>.of(tool.cast<String, Object?>());
      continue;
    }
    final name = tool['name'];
    if (name is! String || name.isEmpty || name == 'DeferredToolPlaceholder') {
      continue;
    }
    final schema = tool['input_schema'];
    if (schema is! Map) continue;
    final description = '${tool['description'] ?? ''}';
    declarations.add({
      'name': antigravityFunctionName(name),
      if (description.isNotEmpty) 'description': description,
      'parametersJsonSchema': schema.isNotEmpty
          ? schema
          : const <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{},
            },
    });
  }

  final choice = body['tool_choice'] is Map ? body['tool_choice'] as Map : null;
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
        calling['mode'] = 'AUTO';
    }
    request['toolConfig'] = {'functionCallingConfig': calling};
  } else if (webSearch != null &&
      choice?['type'] != 'none' &&
      antigravitySupportsWebSearch(model)) {
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
      'parts': [
        {'text': systemParts.join('\n\n')},
      ],
    };
  }

  final generation = <String, Object?>{};
  if (body['max_tokens'] case final num n when n > 0) {
    generation['maxOutputTokens'] = n.toInt();
  }
  if (body['temperature'] case final num t) generation['temperature'] = t;
  if (body['top_p'] case final num p) generation['topP'] = p;
  if (body['top_k'] case final num k) generation['topK'] = k;
  if (body['stop_sequences'] case final List stops when stops.isNotEmpty) {
    generation['stopSequences'] = stops;
  }

  final thinking = geminiThinkingConfig(
    model,
    effort: effort,
    thinking: body['thinking'],
    outputConfig: body['output_config'],
  );
  if (thinking != null) generation['thinkingConfig'] = thinking;
  if (generation.isNotEmpty) request['generationConfig'] = generation;
  return request;
}

/// Thinking configuration for a standard Gemini API request on [model]:
/// `thinkingLevel` for Gemini 3+, `thinkingBudget` for Gemini 2.5 and earlier,
/// or null when neither an effort nor a thinking request was made (or [model]
/// is an image-generation model).
Map<String, Object?>? geminiThinkingConfig(
  String model, {
  String? effort,
  Object? thinking,
  Object? outputConfig,
}) {
  final lower = model.toLowerCase();
  if (lower.contains('image') || lower.contains('imagen')) return null;

  final thinkingMap = thinking is Map ? thinking : null;
  final thinkingType = '${thinkingMap?['type'] ?? ''}'.toLowerCase();
  final budget = switch (thinkingMap?['budget_tokens']) {
    final num n when n > 0 => n.toInt(),
    _ => null,
  };
  final outputEffort = switch (outputConfig) {
    {'effort': final String e} when e.trim().isNotEmpty =>
      e.trim().toLowerCase(),
    _ => null,
  };

  final rawEffort = effort != null && effort.trim().isNotEmpty
      ? effort.trim().toLowerCase()
      : thinkingType == 'disabled'
      ? 'none'
      : outputEffort;

  final generation = lower.contains('gemini-pro-agent')
      ? 3
      : geminiGeneration(lower);

  if (generation >= 3) {
    final level =
        rawEffort ??
        (thinkingType == 'enabled' && budget != null
            ? _budgetToLevel(budget)
            : null);
    if (level == null) {
      if (thinkingType == 'adaptive' || thinkingType == 'enabled') {
        return {'includeThoughts': true};
      }
      return null;
    }
    final flash = lower.contains('flash');
    final thinkingLevel = switch (level) {
      'minimal' => flash ? 'minimal' : 'low',
      'low' || 'none' => 'low',
      'medium' => flash || generation > 3 ? 'medium' : 'high',
      'xhigh' || 'max' => generation >= 4 ? 'xhigh' : 'high',
      _ => 'high',
    };
    return {'includeThoughts': true, 'thinkingLevel': thinkingLevel};
  }

  if (rawEffort == 'none') {
    return {'thinkingBudget': lower.contains('pro') ? 128 : 0};
  }
  if (rawEffort == null && budget == null) {
    if (thinkingType == 'adaptive' || thinkingType == 'enabled') {
      return {'includeThoughts': true, 'thinkingBudget': -1};
    }
    return null;
  }
  final tokens =
      budget ??
      switch (rawEffort) {
        'minimal' || 'low' => 4096,
        'medium' => 8192,
        'high' => 24576,
        'xhigh' || 'max' => 32768,
        _ => 8192,
      };
  return {'includeThoughts': true, 'thinkingBudget': tokens};
}

String _budgetToLevel(int budget) {
  if (budget <= 2048) return 'minimal';
  if (budget <= 6144) return 'low';
  if (budget <= 16384) return 'medium';
  return 'high';
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

void _appendTurn(
  List<Map<String, Object?>> contents,
  String role,
  List<Map<String, Object?>> parts,
) {
  if (contents.isNotEmpty && contents.last['role'] == role) {
    final prev = contents.last['parts'] as List<Map<String, Object?>>;
    final prevHasResponses = prev.any((p) => p.containsKey('functionResponse'));
    final nextHasResponses = parts.any(
      (p) => p.containsKey('functionResponse'),
    );
    if (role != 'user' || prevHasResponses == nextHasResponses) {
      prev.addAll(parts);
      return;
    }
  }
  contents.add({'role': role, 'parts': parts});
}

/// Drops duplicate `tool_result` blocks for the same `tool_use_id` so every
/// `functionResponse` matches its `functionCall` one-to-one.
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

/// Ensures every `model` turn's `functionCall` parts have matching
/// `functionResponse` parts in the immediately following `user` turn.
List<Map<String, Object?>> _pairFunctionTurns(
  List<Map<String, Object?>> contents,
) {
  final out = <Map<String, Object?>>[];
  for (var i = 0; i < contents.length; i++) {
    final turn = contents[i];
    out.add(turn);
    if (turn['role'] != 'model') continue;
    final parts = turn['parts'] as List<Map<String, Object?>>;
    final calls = [
      for (final part in parts)
        if (part['functionCall'] case final Map call) call,
    ];
    if (calls.isEmpty) continue;

    final next = i + 1 < contents.length ? contents[i + 1] : null;
    final nextParts = next != null && next['role'] == 'user'
        ? next['parts'] as List<Map<String, Object?>>
        : null;
    final nextResponses = [
      for (final part in nextParts ?? const <Map<String, Object?>>[])
        if (part['functionResponse'] case final Map response) response,
    ];
    final answeredIds = {
      for (final response in nextResponses)
        if (response['id'] case final String id when id.isNotEmpty) id,
    };
    final missing = <Map<String, Object?>>[];
    var unmatchedResponses = nextResponses
        .where((r) => '${r['id'] ?? ''}'.isEmpty)
        .length;
    for (final call in calls) {
      final id = '${call['id'] ?? ''}';
      if (id.isNotEmpty) {
        if (answeredIds.contains(id)) continue;
      } else if (unmatchedResponses > 0) {
        unmatchedResponses--;
        continue;
      }
      missing.add({
        'functionResponse': {
          'name': '${call['name'] ?? 'tool'}',
          if (id.isNotEmpty) 'id': id,
          'response': {'output': _interrupted},
        },
      });
    }
    if (missing.isEmpty) continue;
    if (nextParts != null && nextResponses.isNotEmpty) {
      nextParts.addAll(missing);
    } else {
      out.add({'role': 'user', 'parts': missing});
    }
  }
  return out;
}

Map<String, Object?>? _inlinePart(Object? source) {
  if (source is! Map) return null;
  return switch (source['type']) {
    'base64' => _base64Part(
      '${source['media_type'] ?? ''}',
      '${source['data'] ?? ''}',
    ),
    'url' when '${source['url'] ?? ''}'.isNotEmpty => {
      'fileData': {
        'mimeType': '${source['media_type'] ?? 'application/octet-stream'}',
        'fileUri': '${source['url']}',
      },
    },
    'text' when '${source['data'] ?? ''}'.isNotEmpty => {
      'text': '${source['data']}',
    },
    _ => null,
  };
}

Map<String, Object?>? _base64Part(String rawMime, String data) {
  if (data.isEmpty) return null;
  var mime = rawMime.trim().toLowerCase();
  if (mime == 'image/jpg') mime = 'image/jpeg';
  if (mime.isEmpty ||
      mime == 'application/octet-stream' ||
      !mime.contains('/')) {
    try {
      mime = imageMediaType(base64Decode(data)) ?? 'image/png';
    } on FormatException {
      mime = 'image/png';
    }
  }
  if (mime.startsWith('image/') && !_geminiImageTypes.contains(mime)) {
    return {
      'text':
          '[An image of type $mime was omitted: Gemini accepts PNG, JPEG, WebP, HEIC and HEIF.]',
    };
  }
  return {
    'inlineData': {'mimeType': mime, 'data': data},
  };
}

(String, List<Map<String, Object?>>) _toolResult(Object? content) {
  if (content is String) return (content, const []);
  if (content is! List) return ('', const []);
  final text = <String>[];
  final media = <Map<String, Object?>>[];
  for (final block in content) {
    if (block is! Map) continue;
    switch (block['type']) {
      case 'text':
        text.add('${block['text'] ?? ''}');
      case 'image' || 'document':
        if (_inlinePart(block['source']) case final part?) {
          if (part.containsKey('text')) {
            text.add('${part['text']}');
          } else {
            media.add(part);
          }
        }
      default:
        text.add(jsonEncode(block));
    }
  }
  return (text.join('\n'), media);
}

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
