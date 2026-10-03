// Ported from CLIProxyAPI's internal/translator/common (MIT License; see
// NOTICE.md beside this file): what the translators use of it.

import 'dart:convert';

import 'json_value.dart';
import 'util.dart';

/// One server-sent event: its name and JSON data, and the blank line that
/// ends it.
String sseEvent(String event, Object? data) =>
    'event: $event\ndata: ${data is String ? data : jsonEncode(data)}\n\n';

/// `count_tokens`' answer.
Map<String, Object?> claudeInputTokens(int count) => {'input_tokens': count};

/// Wraps [text] as Claude Code wraps instructions in a message, so that
/// another provider takes a system message moved into the conversation as
/// a directive rather than as the user's words.
String systemReminderText(String text) =>
    '<system-reminder>\n$text\n</system-reminder>';

/// A Claude message-level `system` content as reminder text for providers
/// whose conversations hold no system messages; null when it has no text.
String? claudeMessageSystemReminderText(JsonValue content) {
  final parts = _claudeSystemTextParts(content);
  if (parts.isEmpty) return null;
  final text = parts.join('\n');
  if (text.trim().isEmpty) return null;
  return systemReminderText(text);
}

List<String> _claudeSystemTextParts(JsonValue content) {
  if (!content.exists) return const [];
  if (content.isString) {
    final text = content.string;
    if (text.isEmpty || isClaudeCodeAttributionSystemText(text)) {
      return const [];
    }
    return [text];
  }
  if (!content.isArray) return const [];
  return [
    for (final item in content.array)
      if (item.get('type').string == 'text')
        if (item.get('text').string case final text
            when text.isNotEmpty && !isClaudeCodeAttributionSystemText(text))
          text,
  ];
}

/// [content]'s `tool_result` blocks in the order of [toolUseIds], the
/// other blocks where they were. As it was when they do not match one to
/// one.
JsonValue alignClaudeToolResults(JsonValue content, List<String> toolUseIds) {
  if (!content.isArray || toolUseIds.isEmpty) return content;
  final parts = content.array;
  final results = <JsonValue>[];
  final slots = <int>[];
  for (final (i, part) in parts.indexed) {
    if (part.get('type').string == 'tool_result') {
      results.add(part);
      slots.add(i);
    }
  }
  if (results.length != toolUseIds.length) return content;
  final reordered = <JsonValue>[];
  final used = List.filled(results.length, false);
  for (final id in toolUseIds) {
    var matched = -1;
    for (final (i, result) in results.indexed) {
      if (!used[i] && id.isNotEmpty && result.get('tool_use_id').string == id) {
        matched = i;
        break;
      }
    }
    if (matched < 0) return content;
    used[matched] = true;
    reordered.add(results[matched]);
  }
  final ordered = [for (final part in parts) part.value];
  for (final (i, slot) in slots.indexed) {
    ordered[slot] = reordered[i].value;
  }
  return JsonValue(ordered);
}

/// Moves each `tool` message to just after the assistant message whose
/// `tool_calls` it answers, by `tool_call_id`, keeping the order
/// otherwise. Histories that are ambiguous, orphaned or incomplete are left
/// as they are.
List<Map<String, Object?>> alignOpenAIToolCallMessages(
  List<Map<String, Object?>> messages, [
  List<String> extraAmbiguousIds = const [],
]) {
  if (messages.length <= 1) return messages;
  final assistants = <({int index, List<String> ids, bool invalid})>[];
  final assistantByCallId = <String, int>{};
  final ambiguous = <String>{
    for (final id in extraAmbiguousIds)
      if (id.trim().isNotEmpty) id.trim(),
  };
  final toolIndexesByCallId = <String, List<int>>{};
  for (final (i, message) in messages.indexed) {
    final value = JsonValue(message);
    switch (value.get('role').string) {
      case 'assistant':
        final calls = value.get('tool_calls');
        if (!calls.isArray || calls.array.isEmpty) continue;
        final ids = <String>[];
        var hasEmpty = false;
        for (final call in calls.array) {
          final id = call.get('id').string;
          if (id.isEmpty) {
            ambiguous.add('');
            hasEmpty = true;
            continue;
          }
          if (assistantByCallId.containsKey(id)) ambiguous.add(id);
          assistantByCallId[id] = i;
          ids.add(id);
        }
        if (ids.isNotEmpty || hasEmpty) {
          assistants.add((index: i, ids: ids, invalid: hasEmpty));
        }
      case 'tool':
        final id = value.get('tool_call_id').string;
        if (id.isEmpty) {
          ambiguous.add('');
        } else {
          final indexes = toolIndexesByCallId.putIfAbsent(id, () => []);
          indexes.add(i);
          if (indexes.length > 1) ambiguous.add(id);
        }
    }
  }
  if (assistants.isEmpty) return messages;
  final groups = <int, List<int>>{};
  for (final assistant in assistants) {
    if (assistant.invalid) continue;
    final matched = <int>[];
    var eligible = true;
    for (final id in assistant.ids) {
      final indexes = toolIndexesByCallId[id] ?? const [];
      if (ambiguous.contains(id) ||
          indexes.length != 1 ||
          indexes.first <= assistant.index) {
        eligible = false;
        break;
      }
      matched.add(indexes.first);
    }
    if (!eligible) continue;
    matched.sort();
    var adjacent = true;
    for (final (offset, index) in matched.indexed) {
      if (index != assistant.index + offset + 1) {
        adjacent = false;
        break;
      }
    }
    if (!adjacent) groups[assistant.index] = matched;
  }
  if (groups.isEmpty) return messages;
  final moved = {for (final indexes in groups.values) ...indexes};
  return [
    for (final (i, message) in messages.indexed)
      if (!moved.contains(i)) ...[
        message,
        for (final index in groups[i] ?? const <int>[]) messages[index],
      ],
  ];
}
