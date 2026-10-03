// Ported from CLIProxyAPI's
// internal/translator/openai/claude/openai_claude_request.go (MIT License;
// see NOTICE.md beside this file).

import 'json_value.dart';
import 'common.dart';
import 'signature.dart';
import 'thinking.dart';
import 'util.dart';

/// An Anthropic Messages request ([request], decoded or as JSON text) as an
/// OpenAI Chat Completions request for [model]: its system prompt,
/// messages, tools and thinking.
///
/// Assistant thinking goes along as `reasoning_content` only when it was
/// signed by a GPT model; with [preserveThinking], for upstreams that take
/// their own reasoning back that way (DeepSeek, Kimi…), whatever its
/// signature.
Map<String, Object?> convertClaudeRequestToOpenAI(
  String model,
  Object? request,
  bool stream, {
  bool preserveThinking = false,
}) {
  final root = JsonValue.of(request);
  final out = <String, Object?>{'model': model, 'messages': <Object?>[]};

  final maxTokens = root.get('max_tokens');
  if (maxTokens.exists) out['max_tokens'] = maxTokens.integer;

  final temperature = root.get('temperature');
  final topP = root.get('top_p');
  if (temperature.exists) {
    out['temperature'] = temperature.number;
  } else if (topP.exists) {
    out['top_p'] = topP.number;
  }

  final stopSequences = root.get('stop_sequences');
  if (stopSequences.isArray) {
    final stops = [for (final stop in stopSequences.array) stop.string];
    if (stops.isNotEmpty) out['stop'] = stops;
  }

  out['stream'] = stream;

  // Claude's thinking budget as OpenAI's reasoning_effort.
  final thinkingConfig = root.get('thinking');
  if (thinkingConfig.isObject) {
    final kind = thinkingConfig.get('type');
    if (kind.exists) {
      final effortSetting = root.get('output_config.effort');
      switch (kind.string) {
        case 'enabled':
          final budget = thinkingConfig.get('budget_tokens');
          if (budget.exists) {
            if (convertBudgetToLevel(budget.integer) case final effort?
                when effort.isNotEmpty) {
              out['reasoning_effort'] = effort;
            }
          } else if (effortSetting.isString &&
              effortSetting.string.trim().isNotEmpty) {
            // Manual thinking paired with an explicit effort: kept, as
            // there is no budget to map.
            out['reasoning_effort'] = effortSetting.string.trim().toLowerCase();
          } else if (convertBudgetToLevel(-1) case final effort?) {
            out['reasoning_effort'] = effort;
          }
        case 'adaptive' || 'auto':
          final effort = effortSetting.isString
              ? effortSetting.string.trim().toLowerCase()
              : '';
          out['reasoning_effort'] = effort.isNotEmpty
              ? effort
              : ThinkingLevel.xhigh;
        case 'disabled':
          if (convertBudgetToLevel(0) case final effort?) {
            out['reasoning_effort'] = effort;
          }
      }
    }
  }

  final messageItems = <Map<String, Object?>>[];

  // The system prompt first.
  final systemItems = <Map<String, Object?>>[];
  final system = root.get('system');
  if (system.exists) {
    if (system.isString) {
      final text = system.string;
      if (text.isNotEmpty && !isClaudeCodeAttributionSystemText(text)) {
        systemItems.add({'type': 'text', 'text': text});
      }
    } else if (system.isArray) {
      for (final item in system.array) {
        if (_convertClaudeContentPart(item) case final part?) {
          systemItems.add(part);
        }
      }
    }
  }
  if (systemItems.isNotEmpty) {
    messageItems.add({'role': 'system', 'content': systemItems});
  }

  final messages = root.get('messages');
  if (messages.isArray) {
    var pendingToolUseIds = <String>[];
    var pendingSystemReminders = <Map<String, Object?>>[];
    final toolNameById = <String, String>{};

    for (final message in messages.array) {
      final role = message.get('role').string;
      var content = message.get('content');
      if (role == 'system') {
        if (claudeMessageSystemReminderText(content) case final reminder?) {
          final item = <String, Object?>{
            'role': 'user',
            'content': [
              {'type': 'text', 'text': reminder},
            ],
          };
          if (pendingToolUseIds.isNotEmpty) {
            pendingSystemReminders.add(item);
          } else {
            messageItems.add(item);
          }
        }
        continue;
      }

      if (content.isArray) {
        if (role == 'user' && pendingToolUseIds.isNotEmpty) {
          content = alignClaudeToolResults(content, pendingToolUseIds);
        }
        final precedingToolCallsPending = pendingToolUseIds.isNotEmpty;
        pendingToolUseIds = [];

        final contentItems = <Map<String, Object?>>[];
        final reasoningParts = <String>[];
        final toolCalls = <Map<String, Object?>>[];
        final toolResults = <Map<String, Object?>>[];
        // Images out of tool results, sent on in a user message.
        final relayedToolImages = <Map<String, Object?>>[];

        for (final part in content.array) {
          switch (part.get('type').string) {
            case 'thinking':
              // Only an assistant's: thinking in another role would be an
              // injection.
              if (role == 'assistant' &&
                  _shouldMapThinkingToReasoning(part, preserveThinking)) {
                final text = thinkingText(part);
                if (text.trim().isNotEmpty) reasoningParts.add(text);
              }
            case 'redacted_thinking':
              // Never reasoning_content.
              break;
            case 'text' || 'image':
              if (_convertClaudeContentPart(part) case final item?) {
                contentItems.add(item);
              }
            case 'tool_use':
              // Only an assistant's.
              if (role == 'assistant') {
                final id = part.get('id').string;
                final name = part.get('name').string;
                if (id.isNotEmpty) {
                  pendingToolUseIds.add(id);
                  if (name.isNotEmpty) toolNameById[id] = name;
                }
                final input = part.get('input');
                toolCalls.add({
                  'id': id,
                  'type': 'function',
                  'function': {
                    'name': name,
                    'arguments': input.exists ? input.raw : '{}',
                  },
                });
              }
            case 'tool_result':
              final id = part.get('tool_use_id').string;
              final result = <String, Object?>{
                'role': 'tool',
                'tool_call_id': id,
                'content': '',
              };
              if (toolNameById[id] case final name? when name.isNotEmpty) {
                result['name'] = name;
              }
              final (text, images) = _convertToolResultContent(
                part.get('content'),
              );
              result['content'] = text;
              relayedToolImages.addAll(images);
              toolResults.add(result);
          }
        }

        final reasoning = reasoningParts.join('\n\n');
        final hasContent = contentItems.isNotEmpty;
        final hasReasoning = reasoning.isNotEmpty;
        final hasToolCalls = toolCalls.isNotEmpty;
        final hasToolResults = toolResults.isNotEmpty;

        // Reminders held for tool results that never came.
        if (precedingToolCallsPending &&
            !hasToolResults &&
            pendingSystemReminders.isNotEmpty) {
          messageItems.addAll(pendingSystemReminders);
          pendingSystemReminders = [];
        }

        // Tool messages must follow the assistant message with the calls:
        // the results first, then held reminders, then this message.
        messageItems.addAll(toolResults);

        // A tool message holds no images: they follow in a user message.
        if (relayedToolImages.isNotEmpty) {
          final relay = <Map<String, Object?>>[
            {'type': 'text', 'text': _toolResultImageRelayNotice},
            ...relayedToolImages,
          ];
          if (role == 'user' && hasContent) {
            // One user turn: into this message.
            contentItems.insertAll(0, relay);
          } else {
            messageItems.add({'role': 'user', 'content': relay});
          }
        }

        if (pendingSystemReminders.isNotEmpty) {
          messageItems.addAll(pendingSystemReminders);
          pendingSystemReminders = [];
        }

        if (role == 'assistant') {
          // One message with the text, calls and reasoning: split, the
          // calls would be cut off from their results.
          if (hasContent || hasReasoning || hasToolCalls) {
            messageItems.add({
              'role': 'assistant',
              'content': hasContent ? contentItems : '',
              if (hasReasoning) 'reasoning_content': reasoning,
              if (hasToolCalls) 'tool_calls': toolCalls,
            });
          }
        } else if (hasContent) {
          messageItems.add({'role': role, 'content': contentItems});
        }
      } else if (content.isString) {
        messageItems.add({'role': role, 'content': content.string});
      }
    }
    messageItems.addAll(pendingSystemReminders);
  }

  if (messageItems.isNotEmpty) {
    out['messages'] = alignOpenAIToolCallMessages(messageItems);
  }

  // Anthropic's tools as OpenAI's functions.
  final tools = root.get('tools');
  if (tools.isArray) {
    final items = <Map<String, Object?>>[
      for (final tool in tools.array)
        {
          'type': 'function',
          'function': {
            'name': tool.get('name').string,
            'description': tool.get('description').string,
            'parameters': switch (tool.get('input_schema')) {
              final schema when schema.exists && !schema.isNull =>
                _normalizeObjectSchemaProperties(jsonCopy(schema.value)),
              _ => <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{},
              },
            },
          },
        },
    ];
    if (items.isNotEmpty) out['tools'] = items;
  }

  final toolChoice = root.get('tool_choice');
  if (toolChoice.exists && !toolChoice.isNull) {
    var choiceType = toolChoice.get('type').string;
    if (choiceType.isEmpty && toolChoice.isString) {
      choiceType = toolChoice.string;
    }
    out['tool_choice'] = switch (choiceType) {
      'auto' => 'auto',
      'any' => 'required',
      'none' => 'none',
      'tool' => switch (toolChoice.get('name').string) {
        '' => 'none',
        final name => {
          'type': 'function',
          'function': {'name': name},
        },
      },
      // Fail closed: what is not understood grants nothing.
      _ => 'none',
    };
    if (toolChoice.get('disable_parallel_tool_use').value == true) {
      out['parallel_tool_calls'] = false;
    }
  }

  final user = root.get('user');
  if (user.exists) out['user'] = user.string;

  return out;
}

/// A schema as strict OpenAPI 3.0 validators take it: `true` subschemas as
/// `{}`, objects with `properties`, and no patterns they cannot compile.
Object? _normalizeObjectSchemaProperties(Object? schema) {
  switch (schema) {
    case true:
      return <String, Object?>{};
    case final Map<String, Object?> value:
      if (value['type'] == 'object' && !value.containsKey('properties')) {
        value['properties'] = <String, Object?>{};
      }
      if (value['pattern'] case final String pattern
          when hasUnsupportedUnicodePropertyEscape(pattern)) {
        value.remove('pattern');
      }
      if (value['patternProperties'] case final Map<String, Object?> props) {
        for (final key in props.keys.toList()) {
          if (hasUnsupportedUnicodePropertyEscape(key)) {
            props.remove(key);
          } else {
            props[key] = _normalizeObjectSchemaProperties(props[key]);
          }
        }
      }
      for (final keyword in schemaMapKeywords) {
        if (keyword == 'patternProperties') continue;
        if (value[keyword] case final Map<String, Object?> sub) {
          for (final key in sub.keys.toList()) {
            sub[key] = _normalizeObjectSchemaProperties(sub[key]);
          }
        }
      }
      for (final keyword in schemaValueKeywords) {
        if (!value.containsKey(keyword)) continue;
        switch (value[keyword]) {
          case true when keyword != 'additionalProperties':
            // additionalProperties stays a boolean, as structured outputs
            // need it.
            value[keyword] = <String, Object?>{};
          case final Map<String, Object?> sub:
            value[keyword] = _normalizeObjectSchemaProperties(sub);
          case final List<Object?> items:
            for (var i = 0; i < items.length; i++) {
              items[i] = _normalizeObjectSchemaProperties(items[i]);
            }
        }
      }
      return value;
    case final List<Object?> items:
      for (var i = 0; i < items.length; i++) {
        items[i] = _normalizeObjectSchemaProperties(items[i]);
      }
      return items;
    default:
      return schema;
  }
}

bool _shouldMapThinkingToReasoning(JsonValue part, bool preserve) {
  if (preserve) return true;
  final signature = part.get('signature');
  if (!signature.exists || signature.string.trim().isEmpty) return false;
  return compatibleGptSignature(signature.string) != null;
}

Map<String, Object?>? _convertClaudeContentPart(JsonValue part) {
  switch (part.get('type').string) {
    case 'text':
      final text = part.get('text').string;
      if (text.trim().isEmpty || isClaudeCodeAttributionSystemText(text)) {
        return null;
      }
      return {'type': 'text', 'text': text};
    case 'image':
      var url = '';
      final source = part.get('source');
      if (source.exists) {
        switch (source.get('type').string) {
          case 'base64':
            var mediaType = source.get('media_type').string;
            if (mediaType.isEmpty) mediaType = 'application/octet-stream';
            final data = source.get('data').string;
            if (data.isNotEmpty) url = 'data:$mediaType;base64,$data';
          case 'url':
            url = source.get('url').string;
        }
      }
      if (url.isEmpty) url = part.get('url').string;
      if (url.isEmpty) return null;
      return {
        'type': 'image_url',
        'image_url': {'url': url},
      };
    default:
      return null;
  }
}

/// Keeps a tool message from being empty when its result was images alone.
const toolResultImagePlaceholder =
    '[Tool returned image content; the images follow in the next user message.]';

/// Heads the user message that carries a tool's images.
const _toolResultImageRelayNotice =
    'Images returned by the preceding tool call(s):';

/// A tool result's content as a tool message's text, and the images in it.
(String, List<Map<String, Object?>>) _convertToolResultContent(
  JsonValue content,
) {
  if (!content.exists) return ('', const []);
  if (content.isString) return (content.string, const []);
  if (content.isArray) {
    final parts = <String>[];
    final images = <Map<String, Object?>>[];
    for (final item in content.array) {
      final type = item.get('type').string;
      if (item.isString) {
        parts.add(item.string);
      } else if (item.isObject && type == 'text') {
        parts.add(item.get('text').string);
      } else if (item.isObject && type == 'image') {
        if (_convertClaudeContentPart(item) case final image?) {
          images.add(image);
        } else {
          parts.add(item.raw);
        }
      } else if (item.isObject && item.get('text').isString) {
        parts.add(item.get('text').string);
      } else {
        parts.add(item.raw);
      }
    }
    final joined = parts.join('\n\n');
    if (joined.trim().isEmpty) {
      return images.isNotEmpty
          ? (toolResultImagePlaceholder, images)
          : (content.raw, const []);
    }
    return (joined, images);
  }
  if (content.isObject) {
    if (content.get('type').string == 'image') {
      if (_convertClaudeContentPart(content) case final image?) {
        return (toolResultImagePlaceholder, [image]);
      }
    }
    final text = content.get('text');
    if (text.isString) return (text.string, const []);
    return (content.raw, const []);
  }
  return (content.raw, const []);
}
