// Ported from CLIProxyAPI's
// internal/translator/codex/claude/codex_claude_request.go (MIT License;
// see NOTICE.md beside this file), for the standard OpenAI Responses API
// rather than ChatGPT's Codex backend.

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'json_value.dart';
import 'common.dart';
import 'signature.dart';
import 'thinking.dart';
import 'util.dart';

/// Longest name or `call_id` the Responses API takes.
const _nameLimit = 64;

/// An Anthropic Messages request ([request], decoded or as JSON text) as an
/// OpenAI Responses request for [model], streamed.
///
/// With [reasoning] (a model that thinks), Claude's thinking budget goes
/// as `reasoning.effort` and signed GPT reasoning is replayed as encrypted
/// reasoning items; without it neither is asked for, as models that do not
/// think refuse them.
Map<String, Object?> convertClaudeRequestToResponses(
  String model,
  Object? request, {
  bool reasoning = true,
}) {
  final root = JsonValue.of(request);
  final toolNameMap = buildShortToolNameMap(root);
  final out = <String, Object?>{'model': model, 'input': <Object?>[]};
  final inputItems = <Map<String, Object?>>[];

  // The system prompt as a developer message.
  final system = root.get('system');
  if (system.exists) {
    final parts = <Map<String, Object?>>[];
    void add(String text) {
      if (text.isEmpty || isClaudeCodeAttributionSystemText(text)) return;
      parts.add({'type': 'input_text', 'text': text});
    }

    if (system.isString) {
      add(system.string);
    } else if (system.isArray) {
      for (final item in system.array) {
        if (item.get('type').string == 'text') add(item.get('text').string);
      }
    }
    if (parts.isNotEmpty) {
      inputItems.add({
        'type': 'message',
        'role': 'developer',
        'content': parts,
      });
    }
  }

  final messages = root.get('messages');
  if (messages.isArray) {
    var pendingToolUseIds = <String>[];
    var pendingReminders = <Map<String, Object?>>[];

    void flushReminders() {
      inputItems.addAll(pendingReminders);
      pendingReminders = [];
    }

    for (final message in messages.array) {
      final role = message.get('role').string;
      if (role == 'system') {
        if (claudeMessageSystemReminderText(message.get('content'))
            case final reminder?) {
          final item = <String, Object?>{
            'type': 'message',
            'role': 'user',
            'content': [
              {'type': 'input_text', 'text': reminder},
            ],
          };
          if (pendingToolUseIds.isNotEmpty) {
            pendingReminders.add(item);
          } else {
            inputItems.add(item);
          }
        }
        continue;
      }

      var contents = message.get('content');
      if (role == 'user' && pendingToolUseIds.isNotEmpty && contents.isArray) {
        contents = alignClaudeToolResults(contents, pendingToolUseIds);
      }
      pendingToolUseIds = [];
      final contentItems = <Map<String, Object?>>[];

      void flushMessage() {
        if (contentItems.isEmpty) return;
        inputItems.add({
          'type': 'message',
          'role': role,
          'content': [...contentItems],
        });
        contentItems.clear();
      }

      void addText(String text) => contentItems.add({
        'type': role == 'assistant' ? 'output_text' : 'input_text',
        'text': text,
      });

      void addReasoning(JsonValue part) {
        if (role != 'assistant' || !reasoning) return;
        final raw = part.get('signature').string;
        var signature = compatibleGptSignature(raw);
        if (signature == null) {
          if (!_acceptsGrokSignature(model) ||
              !isValidGrokEncryptedContent(raw)) {
            return;
          }
          signature = raw;
        }
        flushMessage();
        inputItems.add({
          'type': 'reasoning',
          'summary': <Object?>[],
          'content': null,
          'encrypted_content': signature,
        });
      }

      if (contents.isArray) {
        for (final content in contents.array) {
          switch (content.get('type').string) {
            case 'text':
              flushReminders();
              addText(content.get('text').string);
            case 'thinking':
              addReasoning(content);
            case 'image':
              flushReminders();
              if (_dataUrl(content.get('source')) case final url?) {
                contentItems.add({'type': 'input_image', 'image_url': url});
              }
            case 'document':
              flushReminders();
              final source = content.get('source');
              if (source.get('type').string != 'base64') continue;
              final mediaType = source.get('media_type').string.trim();
              if (mediaType.toLowerCase() != 'application/pdf') continue;
              var data = source.get('data').string;
              if (data.isEmpty) data = source.get('base64').string;
              if (data.isNotEmpty) {
                contentItems.add({
                  'type': 'input_file',
                  'file_data': 'data:$mediaType;base64,$data',
                  'filename': 'document.pdf',
                });
              }
            case 'tool_use':
              flushMessage();
              final id = content.get('id').string;
              if (id.isNotEmpty) pendingToolUseIds.add(id);
              final name = content.get('name').string;
              inputItems.add({
                'type': 'function_call',
                'call_id': shortenCallIdIfNeeded(id),
                'name': toolNameMap[name] ?? shortenNameIfNeeded(name),
                'arguments': content.get('input').raw,
              });
            case 'tool_result':
              flushMessage();
              final output = <String, Object?>{
                'type': 'function_call_output',
                'call_id': shortenCallIdIfNeeded(
                  content.get('tool_use_id').string,
                ),
              };
              final result = content.get('content');
              if (result.isArray) {
                final parts = <Map<String, Object?>>[];
                for (final part in result.array) {
                  switch (part.get('type').string) {
                    case 'image':
                      if (_dataUrl(part.get('source')) case final url?) {
                        parts.add({'type': 'input_image', 'image_url': url});
                      }
                    case 'text':
                      parts.add({
                        'type': 'input_text',
                        'text': part.get('text').string,
                      });
                  }
                }
                output['output'] = parts.isNotEmpty ? parts : result.string;
              } else {
                output['output'] = result.string;
              }
              inputItems.add(output);
          }
        }
        flushMessage();
        flushReminders();
      } else if (contents.isString) {
        addText(contents.string);
        flushMessage();
        flushReminders();
      }
    }
    flushReminders();
  }

  // The tools, Claude's web search as the Responses API's own.
  final tools = root.get('tools');
  List<Map<String, Object?>>? toolItems;
  if (tools.isArray) {
    final webSearchNames = {
      for (final tool in tools.array)
        if (isClaudeWebSearchToolType(tool.get('type').string))
          if (tool.get('name').string case final name when name.isNotEmpty)
            name,
    };
    out['tool_choice'] = _convertToolChoice(
      root.get('tool_choice'),
      toolNameMap,
      webSearchNames,
    );
    toolItems = [];
    for (final tool in tools.array) {
      if (isClaudeWebSearchToolType(tool.get('type').string)) {
        toolItems.add(_convertWebSearchTool(tool));
        continue;
      }
      final item =
          (jsonCopy(tool.value) as Map?)?.cast<String, Object?>() ??
          <String, Object?>{};
      if (tool.get('type').string != 'function' || !tool.get('type').isString) {
        item['type'] = 'function';
      }
      final nameValue = tool.get('name');
      if (nameValue.exists) {
        final original = nameValue.string;
        final name = toolNameMap[original] ?? shortenNameIfNeeded(original);
        if (!nameValue.isString || name != original) item['name'] = name;
      }
      item['parameters'] = jsonDecode(
        normalizeToolParameters(tool.get('input_schema')),
      );
      item
        ..remove('input_schema')
        ..remove('cache_control')
        ..remove('defer_loading');
      if (item['parameters'] case final Map<String, Object?> parameters) {
        parameters.remove(r'$schema');
      }
      if (item['strict'] != false) item['strict'] = false;
      toolItems.add(item);
    }
  }

  // Parallel tool calls unless the tool choice says otherwise.
  final disableParallel = root.get('tool_choice.disable_parallel_tool_use');
  out['parallel_tool_calls'] = disableParallel.exists
      ? !disableParallel.boolean
      : true;

  if (reasoning) {
    // Claude's thinking budget as the reasoning effort.
    var effort = ThinkingLevel.medium;
    final thinkingConfig = root.get('thinking');
    if (thinkingConfig.isObject) {
      switch (thinkingConfig.get('type').string) {
        case 'enabled':
          final budget = thinkingConfig.get('budget_tokens');
          if (budget.exists) {
            if (convertBudgetToLevel(budget.integer) case final level?
                when level.isNotEmpty) {
              effort = level;
            }
          }
        case 'adaptive' || 'auto':
          final setting = root.get('output_config.effort');
          final level = setting.isString
              ? setting.string.trim().toLowerCase()
              : '';
          effort = level.isNotEmpty ? level : ThinkingLevel.xhigh;
        case 'disabled':
          if (convertBudgetToLevel(0) case final level?) effort = level;
      }
    }
    out['reasoning'] = {'effort': effort};
  }
  var serviceTier = _normalizeServiceTier(root.get('service_tier'));
  final speed = root.get('speed');
  if (speed.isString && speed.string == 'fast') serviceTier = 'priority';
  if (serviceTier.isNotEmpty) out['service_tier'] = serviceTier;
  out['stream'] = true;
  out['store'] = false;
  // The reasoning comes back encrypted, to be replayed: nothing is stored.
  if (reasoning) out['include'] = ['reasoning.encrypted_content'];

  // Claude's structured output as the Responses API's text format.
  final format = root.get('output_config.format');
  if (format.isObject &&
      format.get('type').string == 'json_schema' &&
      format.get('schema').isObject) {
    final name = switch (format.get('name').string) {
      '' => 'cli_proxy_structured_output',
      final name => name,
    };
    var strict = format.get('strict').value != false;
    // Strict mode needs every property required: rather than a schema
    // the upstream refuses, not strict.
    if (strict && schemaMissesRequired(format.get('schema'))) strict = false;
    out['text'] = {
      'format': {
        'type': 'json_schema',
        'name': name,
        'strict': strict,
        'schema': jsonCopy(format.get('schema').value),
      },
    };
  }

  if (toolItems != null) out['tools'] = toolItems;
  out['input'] = inputItems;
  return out;
}

String? _dataUrl(JsonValue source) {
  if (!source.exists) return null;
  var data = source.get('data').string;
  if (data.isEmpty) data = source.get('base64').string;
  if (data.isEmpty) return null;
  var mediaType = source.get('media_type').string;
  if (mediaType.isEmpty) mediaType = source.get('mime_type').string;
  if (mediaType.isEmpty) mediaType = 'application/octet-stream';
  return 'data:$mediaType;base64,$data';
}

bool _acceptsGrokSignature(String model) =>
    parseSuffix(model).modelName.trim().toLowerCase().contains('grok');

String _normalizeServiceTier(JsonValue value) {
  if (!value.isString) return '';
  return switch (value.string.trim().toLowerCase()) {
    'fast' || 'priority' => 'priority',
    _ => '',
  };
}

/// [id] within the Responses API's `call_id` limit, kept apart from others
/// by a hash of the whole.
String shortenCallIdIfNeeded(String id) {
  if (utf8.encode(id).length <= _nameLimit) return id;
  final digest = sha256.convert(utf8.encode(id)).bytes.sublist(0, 8);
  final suffix =
      '_${digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  return _truncateBytes(id, _nameLimit - suffix.length) + suffix;
}

/// Whether [type] is one of Claude's web search tools.
bool isClaudeWebSearchToolType(String type) =>
    type == 'web_search_20250305' || type == 'web_search_20260209';

Object? _convertToolChoice(
  JsonValue choice,
  Map<String, String> toolNameMap,
  Set<String> webSearchNames,
) {
  if (!choice.exists || choice.isNull) return 'auto';
  var type = choice.get('type').string;
  if (type.isEmpty && choice.isString) type = choice.string;
  switch (type) {
    case 'any':
      return 'required';
    case 'none':
      return 'none';
    case 'tool':
      final original = choice.get('name').string;
      if (webSearchNames.contains(original)) return {'type': 'web_search'};
      final name = toolNameMap[original] ?? shortenNameIfNeeded(original);
      if (name.isEmpty) return 'auto';
      return {'type': 'function', 'name': name};
    default:
      return 'auto';
  }
}

Map<String, Object?> _convertWebSearchTool(JsonValue tool) {
  final out = <String, Object?>{'type': 'web_search'};
  final domains = tool.get('allowed_domains');
  if (domains.isArray) {
    out['filters'] = {'allowed_domains': jsonCopy(domains.value)};
  }
  final location = tool.get('user_location');
  if (location.isObject) out['user_location'] = jsonCopy(location.value);
  return out;
}

/// A tool's name within the Responses API's limit: an MCP tool keeps its
/// own name after the server's.
String shortenNameIfNeeded(String name) {
  if (utf8.encode(name).length <= _nameLimit) return name;
  if (name.startsWith('mcp__')) {
    final index = name.lastIndexOf('__');
    if (index > 0) {
      return _truncateBytes('mcp__${name.substring(index + 2)}', _nameLimit);
    }
  }
  return _truncateBytes(name, _nameLimit);
}

/// Short names for [names], unique within the request.
Map<String, String> buildShortNameMap(List<String> names) {
  final used = <String>{};
  final map = <String, String>{};
  String unique(String candidate) {
    if (!used.contains(candidate)) return candidate;
    for (var i = 1; ; i++) {
      final suffix = '_$i';
      final allowed = (_nameLimit - suffix.length).clamp(0, _nameLimit);
      final name = _truncateBytes(candidate, allowed) + suffix;
      if (!used.contains(name)) return name;
    }
  }

  for (final name in names) {
    final short = unique(shortenNameIfNeeded(name));
    used.add(short);
    map[name] = short;
  }
  return map;
}

/// The request's tools' names, by their short names' originals.
Map<String, String> buildShortToolNameMap(JsonValue request) {
  final tools = request.get('tools');
  if (!tools.isArray) return {};
  final names = [
    for (final tool in tools.array)
      if (tool.get('name').string case final name when name.isNotEmpty) name,
  ];
  return names.isEmpty ? {} : buildShortNameMap(names);
}

/// The request's tools' original names, by their short names.
Map<String, String> buildReverseToolNameMap(JsonValue request) => {
  for (final MapEntry(:key, :value) in buildShortToolNameMap(request).entries)
    value: key,
};

/// [text] cut to at most [bytes] UTF-8 bytes, as Go slices a string.
String _truncateBytes(String text, int bytes) {
  final encoded = utf8.encode(text);
  if (encoded.length <= bytes) return text;
  return utf8.decode(encoded.sublist(0, bytes), allowMalformed: true);
}

/// A tool's input schema as the Responses API's parameters, as JSON text:
/// an object schema with `properties`, without dialect keywords (`$schema`,
/// `$id`) or patterns upstream validators cannot compile.
String normalizeToolParameters(JsonValue schema) {
  const fallback = '{"type":"object","properties":{}}';
  if (!schema.isObject) return fallback;
  final root = jsonCopy(schema.value)! as Map<String, Object?>;
  _stripDialectKeywords(root);
  final type = root['type'];
  var isObject = false;
  if (type == null || type == '') {
    root['type'] = 'object';
    isObject = true;
  } else if (type == 'object') {
    isObject = true;
  } else if (type is List && type.contains('object')) {
    isObject = true;
  }
  if (isObject && root['properties'] == null) {
    root['properties'] = <String, Object?>{};
  }
  return jsonEncode(root);
}

void _stripDialectKeywords(Object? value) {
  switch (value) {
    case final Map<String, Object?> schema:
      schema
        ..remove(r'$schema')
        ..remove(r'$id');
      if (schema['pattern'] case final String pattern
          when hasUnsupportedUnicodePropertyEscape(pattern)) {
        schema.remove('pattern');
      }
      if (schema['patternProperties'] case final Map<String, Object?> props) {
        for (final key in props.keys.toList()) {
          if (hasUnsupportedUnicodePropertyEscape(key)) {
            props.remove(key);
          } else {
            _stripDialectKeywords(props[key]);
          }
        }
      }
      for (final keyword in schemaMapKeywords) {
        if (keyword == 'patternProperties') continue;
        if (schema[keyword] case final Map<String, Object?> sub) {
          sub.values.forEach(_stripDialectKeywords);
        }
      }
      for (final keyword in schemaValueKeywords) {
        switch (schema[keyword]) {
          case final Map<String, Object?> sub:
            _stripDialectKeywords(sub);
          case final List<Object?> items:
            items.forEach(_stripDialectKeywords);
        }
      }
    case final List<Object?> items:
      items.forEach(_stripDialectKeywords);
  }
}

/// Whether [schema] declares a property its `required` does not list,
/// anywhere in it: strict mode refuses such a schema.
bool schemaMissesRequired(JsonValue schema) {
  if (!schema.isObject) {
    return schema.isArray && schema.array.any(schemaMissesRequired);
  }
  final properties = schema.get('properties');
  if (properties.isObject) {
    final required = schema.get('required');
    if (!required.isArray) return properties.map.isNotEmpty;
    final names = {
      for (final item in required.array)
        if (item.isString) item.string,
    };
    if (properties.map.keys.any((name) => !names.contains(name))) return true;
  }
  for (final keyword in schemaMapKeywords) {
    final children = schema.get(keyword);
    if (children.isObject && children.map.values.any(schemaMissesRequired)) {
      return true;
    }
  }
  for (final keyword in schemaValueKeywords) {
    final child = schema.get(keyword);
    if (child.exists && schemaMissesRequired(child)) return true;
  }
  return false;
}
