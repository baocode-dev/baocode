import 'dart:convert';

/// What agy is told of a conversation it takes up from another model (or
/// joins late): what was said and done since it last took part, slimmed
/// to JSON (who said what, which tools were called with what; not their
/// results, thoughts or pictures), in a `<system-reminder>` before the
/// user's message. The chat leaves reminders out of what it shows.
///
/// [chain] is the conversation's branch (Claude Code's jsonl, oldest
/// first); [syncedUuid] the last message agy saw of it, none for all.
/// [notes] go before it (rules or skills changed since it started). Null
/// when there is nothing it has not seen.
String? handoffReminder(
  List<Map<String, Object?>> chain, {
  String? syncedUuid,
  String? notes,
  int budget = handoffBudget,
}) {
  var start = 0;
  if (syncedUuid != null) {
    final at = chain.indexWhere((entry) => entry['uuid'] == syncedUuid);
    if (at >= 0) start = at + 1;
  }
  // Since the last compaction, the summary of what was before in it.
  for (var i = chain.length - 1; i >= start; i--) {
    if (chain[i] case {'type': 'system', 'subtype': 'compact_boundary'}) {
      start = i + 1;
      break;
    }
  }
  final messages = slimMessages(chain.sublist(start));
  if (messages.isEmpty && (notes == null || notes.isEmpty)) return null;
  final kept = _withinBudget(messages, budget);
  final left = messages.length - kept.length;
  return [
    '<system-reminder>',
    if (notes != null && notes.isNotEmpty) ...[notes, ''],
    if (messages.isNotEmpty) ...[
      syncedUuid == null
          ? 'This conversation began with another model before you joined '
                'it. What was said and done follows, as JSON, for you to '
                'take it up from.'
          : 'This conversation went on with another model since you last '
                'took part in it. What was said and done since follows, as '
                'JSON, for you to take it up from.',
      'Tool results are left out: read files again where you need what is '
          'in them. Do not mention this note to the user.',
      if (left > 0) '($left earlier messages left out.)',
      for (final message in kept) jsonEncode(message),
    ],
    '</system-reminder>',
  ].join('\n');
}

/// About 16k tokens, a byte each at most.
const handoffBudget = 16000;

/// The longest a text or a tool's input value is kept.
const _maxText = 4000;
const _maxValue = 600;

/// [entries] as `{role, text, tools}`: the user's words and the answers
/// given, each call made as its name and input; consecutive answers as one.
List<Map<String, Object?>> slimMessages(List<Map<String, Object?>> entries) {
  final messages = <Map<String, Object?>>[];
  for (final entry in entries) {
    final type = entry['type'];
    if (type != 'user' && type != 'assistant') continue;
    if (entry['isMeta'] == true || entry['isApiErrorMessage'] == true) {
      continue;
    }
    final message = entry['message'];
    if (message is! Map) continue;
    final texts = <String>[];
    final tools = <Map<String, Object?>>[];
    final content = message['content'];
    for (final block
        in content is String
            ? [
                {'type': 'text', 'text': content},
              ]
            : content is List
            ? content
            : const []) {
      if (block is! Map) continue;
      switch (block['type']) {
        case 'text':
          final text = withoutReminders('${block['text'] ?? ''}');
          if (text.isNotEmpty) texts.add(_cut(text, _maxText));
        case 'image':
          texts.add('[image]');
        case 'tool_use':
          tools.add({
            'name': '${block['name']}',
            'input': _slimInput(block['input']),
          });
      }
    }
    if (texts.isEmpty && tools.isEmpty) continue;
    final role = type == 'user'
        ? (entry['isCompactSummary'] == true ? 'summary' : 'user')
        : 'assistant';
    final last = messages.lastOrNull;
    if (role == 'assistant' && last != null && last['role'] == 'assistant') {
      if (texts.isNotEmpty) {
        last['text'] = [?last['text'] as String?, ...texts].join('\n\n');
      }
      if (tools.isNotEmpty) {
        last['tools'] = [...?last['tools'] as List?, ...tools];
      }
      continue;
    }
    messages.add({
      'role': role,
      if (texts.isNotEmpty) 'text': texts.join('\n\n'),
      if (tools.isNotEmpty) 'tools': tools,
    });
  }
  return messages;
}

Object? _slimInput(Object? input) => switch (input) {
  final String text => _cut(text, _maxValue),
  final Map<Object?, Object?> map => {
    for (final MapEntry(:key, :value) in map.entries) '$key': _slimInput(value),
  },
  final List<Object?> list => [
    for (final value in list.take(20)) _slimInput(value),
  ],
  _ => input,
};

/// The first message and as many of the last as fit [budget] bytes.
List<Map<String, Object?>> _withinBudget(
  List<Map<String, Object?>> messages,
  int budget,
) {
  int size(Map<String, Object?> message) =>
      utf8.encode(jsonEncode(message)).length + 1;
  final total = messages.fold(0, (sum, message) => sum + size(message));
  if (total <= budget || messages.length < 2) return messages;
  final first = messages.first;
  var left = budget - size(first);
  final last = <Map<String, Object?>>[];
  for (final message in messages.skip(1).toList().reversed) {
    final bytes = size(message);
    if (bytes > left) break;
    left -= bytes;
    last.add(message);
  }
  return [first, ...last.reversed];
}

String _cut(String text, int most) =>
    text.length <= most ? text : '${text.substring(0, most)}…';

final _reminders = RegExp(r'<system-reminder>[\s\S]*?(</system-reminder>|$)');

/// [text] without the notes the app adds to what the user writes (each a
/// `<system-reminder>`).
String withoutReminders(String text) {
  if (!text.contains('<system-r')) return text.trim();
  return text.replaceAll(_reminders, '').trim();
}
