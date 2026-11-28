import 'dart:convert';

/// What agy is told of a conversation it takes up from another model (or
/// joins late): what was said and done since it last took part, in a
/// `<system-reminder>` before the user's message. The chat leaves reminders
/// out of what it shows.
///
/// [chain] is the conversation's branch (Claude Code's jsonl, oldest
/// first); [syncedUuid] the last message agy saw of it, none for all.
/// [notes] go before it (rules or skills changed since it started).
/// [transcriptFile] is an optional path to the full, lossless markdown
/// transcript written alongside the session (see [handoffTranscript]);
/// [sessionFile] is an optional path to the underlying Claude Code jsonl
/// session file. Null when there is nothing it has not seen.
String? handoffReminder(
  List<Map<String, Object?>> chain, {
  String? syncedUuid,
  String? notes,
  String? transcriptFile,
  String? sessionFile,
  int budget = handoffBudget,
}) {
  final unseen = _unseenEntries(chain, syncedUuid: syncedUuid);
  final messages = slimMessages(unseen);
  if (messages.isEmpty && (notes == null || notes.isEmpty)) return null;
  final fitted = _withinBudget(messages, budget);
  final left = messages.length - fitted.kept.length;
  final hasTranscriptFile =
      transcriptFile != null && transcriptFile.isNotEmpty;
  final hasSessionFile = sessionFile != null && sessionFile.isNotEmpty;
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
      if (hasTranscriptFile)
        'Full lossless transcript (including complete tool calls and tool '
            'results) is saved at: $transcriptFile'
      else if (hasSessionFile)
        'Full raw session log (JSONL) is at: $sessionFile',
      if (hasTranscriptFile && hasSessionFile)
        'Raw session log (JSONL): $sessionFile',
      if (hasTranscriptFile)
        'Tool results are omitted inline below; read $transcriptFile '
            '(or the files themselves) whenever you need exact tool output '
            'or omitted details. Do not mention this note to the user.'
      else
        'Tool results are left out: read files again where you need what is '
            'in them. Do not mention this note to the user.',
      if (left > 0)
        hasTranscriptFile
            ? '($left earlier messages left out inline; see $transcriptFile '
                  'for the complete history.)'
            : '($left earlier messages left out.)',
      for (final message in fitted.kept) jsonEncode(message),
    ],
    '</system-reminder>',
  ].join('\n');
}

/// Renders the unseen portion of [chain] after [syncedUuid] (and after the
/// last compaction boundary, if any) into a clean, lossless Markdown
/// transcript containing every user message, assistant reply, tool call
/// input, and tool result on the active branch.
///
/// Returns null when there are no unseen user/assistant messages.
String? handoffTranscript(
  List<Map<String, Object?>> chain, {
  String? syncedUuid,
}) {
  final unseen = _unseenEntries(chain, syncedUuid: syncedUuid);
  final sections = <String>[];
  final toolNamesById = <String, String>{};
  var turn = 0;

  for (final entry in unseen) {
    final type = entry['type'];
    if (type != 'user' && type != 'assistant') continue;
    if (entry['isMeta'] == true || entry['isApiErrorMessage'] == true) {
      continue;
    }
    final message = entry['message'];
    if (message is! Map) continue;
    final content = message['content'];
    final blocks = content is String
        ? [
            {'type': 'text', 'text': content},
          ]
        : content is List
        ? content
        : const <Object?>[];

    final ts = entry['timestamp'];
    final tsSuffix = ts is String && ts.isNotEmpty ? ' ($ts)' : '';
    final model = message['model'];
    final modelSuffix = model is String && model.isNotEmpty ? ' [$model]' : '';

    final parts = <String>[];
    for (final block in blocks) {
      if (block is! Map) continue;
      switch (block['type']) {
        case 'text':
          final text = withoutReminders('${block['text'] ?? ''}');
          if (text.isNotEmpty) parts.add(text);
        case 'image':
          parts.add('[image]');
        case 'tool_use':
          final id = '${block['id'] ?? ''}';
          final name = '${block['name'] ?? 'tool'}';
          if (id.isNotEmpty) toolNamesById[id] = name;
          final idLabel = id.isNotEmpty ? ' ($id)' : '';
          final inputText = _formatLosslessJson(block['input']);
          parts.add('### Tool Call: $name$idLabel\n```json\n$inputText\n```');
        case 'tool_result':
          final id = '${block['tool_use_id'] ?? ''}';
          final name = toolNamesById[id];
          final isError = block['is_error'] == true;
          final label = [
            ?name,
            if (id.isNotEmpty) '($id)',
            if (isError) '[ERROR]',
          ].join(' ');
          final header = label.isEmpty
              ? '### Tool Result'
              : '### Tool Result: $label';
          final body = _formatToolResultContent(block['content']);
          parts.add('$header\n$body');
      }
    }
    if (parts.isEmpty) continue;

    final isOnlyToolResults =
        type == 'user' &&
        blocks.every((b) => b is Map && b['type'] == 'tool_result');
    if (isOnlyToolResults) {
      sections.add(parts.join('\n\n'));
      continue;
    }

    turn++;
    final heading = switch (type) {
      'user' when entry['isCompactSummary'] == true =>
        '## [$turn] Summary$tsSuffix',
      'user' => '## [$turn] User$tsSuffix',
      _ => '## [$turn] Assistant$modelSuffix$tsSuffix',
    };
    sections.add('$heading\n\n${parts.join('\n\n')}');
  }

  if (sections.isEmpty) return null;
  return [
    '# Conversation Handoff Transcript',
    '',
    'Lossless active-branch history exported for Antigravity ACP handoff '
        '(excluding internal metadata and thinking traces).',
    '',
    sections.join('\n\n---\n\n'),
    '',
  ].join('\n');
}

/// Inline handoff budget in UTF-8 bytes (~40k-55k tokens for mixed CJK/English),
/// generous enough to carry full conversation text across long sessions while
/// letting tool payloads degrade cleanly to summaries when needed.
const handoffBudget = 160000;

/// Maximum characters kept per text block and per tool input value in
/// [slimMessages].
const _maxText = 16000;
const _maxValue = 600;

List<Map<String, Object?>> _unseenEntries(
  List<Map<String, Object?>> chain, {
  String? syncedUuid,
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
  return chain.sublist(start);
}

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

String _formatLosslessJson(Object? value) {
  try {
    return jsonEncode(_stripBinaryBlobs(value));
  } on Object {
    return '$value';
  }
}

Object? _stripBinaryBlobs(Object? value) => switch (value) {
  final Map<Object?, Object?> map => {
    for (final MapEntry(:key, :value) in map.entries)
      '$key': key == 'data' && value is String && value.length > 1024
          ? '[base64 data omitted: ${value.length} chars]'
          : _stripBinaryBlobs(value),
  },
  final List<Object?> list => [for (final item in list) _stripBinaryBlobs(item)],
  _ => value,
};

String _formatToolResultContent(Object? content) {
  if (content == null) return '(empty)';
  if (content is String) return content.isEmpty ? '(empty)' : content;
  if (content is List) {
    final parts = <String>[];
    for (final item in content) {
      if (item is Map) {
        switch (item['type']) {
          case 'text':
            final text = '${item['text'] ?? ''}';
            if (text.isNotEmpty) parts.add(text);
          case 'image':
            parts.add('[image]');
          default:
            parts.add(_formatLosslessJson(item));
        }
      } else if (item != null) {
        parts.add('$item');
      }
    }
    return parts.isEmpty ? '(empty)' : parts.join('\n');
  }
  return _formatLosslessJson(content);
}

int _encodedBytes(Map<String, Object?> message) =>
    utf8.encode(jsonEncode(message)).length + 1;

/// Replaces detailed `tools` inputs with compact `{toolName: count}` counts
/// so conversation text is preserved ahead of verbose tool arguments.
Map<String, Object?> _compactTools(Map<String, Object?> message) {
  final tools = message['tools'];
  if (tools is! List || tools.isEmpty) return message;
  final counts = <String, int>{};
  for (final tool in tools) {
    if (tool is Map) {
      final name = '${tool['name'] ?? 'tool'}';
      counts[name] = (counts[name] ?? 0) + 1;
    }
  }
  return {
    for (final entry in message.entries)
      if (entry.key != 'tools') entry.key: entry.value,
    if (counts.isNotEmpty) 'tools_summary': counts,
  };
}

/// Truncates [message]'s `text` so its encoded JSON fits within [maxBytes],
/// dropping verbose `tools` first if needed. Keeps the tail of the text when
/// [keepTail] is true (useful for the latest assistant message whose conclusion
/// is usually at the end).
Map<String, Object?> _fitSingleMessage(
  Map<String, Object?> message,
  int maxBytes, {
  bool keepTail = false,
}) {
  var candidate = message;
  if (_encodedBytes(candidate) <= maxBytes) return candidate;
  candidate = _compactTools(candidate);
  if (_encodedBytes(candidate) <= maxBytes) return candidate;
  final text = candidate['text'];
  if (text is! String || text.isEmpty) {
    return {'role': candidate['role']};
  }
  final shell = {
    for (final entry in candidate.entries)
      if (entry.key != 'text') entry.key: entry.value,
  };
  final shellBytes = _encodedBytes({...shell, 'text': ''});
  final available = maxBytes - shellBytes;
  if (available <= 8) {
    return {'role': candidate['role']};
  }
  final truncated = _cutUtf8(text, available, keepTail: keepTail);
  final result = {...shell, 'text': truncated};
  if (_encodedBytes(result) <= maxBytes) return result;
  // JSON escaping (e.g. \n, \", \uXXXX) can expand bytes beyond raw UTF-8;
  // shrink via binary search on code-point count until encoded size fits.
  final runes = text.runes.toList();
  var lo = 0;
  var hi = runes.length;
  var best = '';
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    final slice = keepTail
        ? '…${String.fromCharCodes(runes.sublist(runes.length - mid))}'
        : '${String.fromCharCodes(runes.sublist(0, mid))}…';
    if (_encodedBytes({...shell, 'text': slice}) <= maxBytes) {
      best = slice;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return {...shell, 'text': best};
}

/// Fits [messages] within [budget] UTF-8 bytes without ever dropping the latest
/// message just because its tool calls or text are large:
/// 1. If everything fits, keep all messages verbatim.
/// 2. Otherwise, compact `tools` -> `tools_summary` from oldest to newest
///    until everything fits, preserving 100% of conversation text.
/// 3. If text alone still exceeds [budget], keep the first message and as many
///    of the latest messages as fit, truncating the latest message if it alone
///    exceeds the remaining budget instead of dropping the entire tail.
({List<Map<String, Object?>> kept}) _withinBudget(
  List<Map<String, Object?>> messages,
  int budget,
) {
  if (messages.isEmpty) return (kept: const []);
  final sizes = [for (final m in messages) _encodedBytes(m)];
  var total = sizes.fold(0, (sum, bytes) => sum + bytes);
  if (total <= budget) return (kept: messages);

  // Stage 1: preserve all turns by compacting tool inputs oldest-first.
  final working = [...messages];
  for (var i = 0; i < working.length && total > budget; i++) {
    if (!working[i].containsKey('tools')) continue;
    final compacted = _compactTools(working[i]);
    final nextSize = _encodedBytes(compacted);
    total += nextSize - sizes[i];
    working[i] = compacted;
    sizes[i] = nextSize;
  }
  if (total <= budget) return (kept: working);

  if (working.length == 1) {
    return (kept: [_fitSingleMessage(working.single, budget, keepTail: true)]);
  }

  // Stage 2: keep the first message (bounded so it cannot starve the tail)
  // and as many of the latest messages as fit.
  final firstCap = (budget ~/ 3).clamp(128, budget);
  final first = sizes.first > firstCap
      ? _fitSingleMessage(working.first, firstCap)
      : working.first;
  var left = budget - _encodedBytes(first);
  if (left <= 0) {
    return (kept: [_fitSingleMessage(working.last, budget, keepTail: true)]);
  }

  final last = <Map<String, Object?>>[];
  for (var i = working.length - 1; i >= 1; i--) {
    final bytes = sizes[i];
    if (bytes <= left) {
      left -= bytes;
      last.add(working[i]);
      continue;
    }
    if (last.isEmpty) {
      // Never drop the most recent turn completely; fit its text into `left`.
      final fitted = _fitSingleMessage(working[i], left, keepTail: true);
      if (_encodedBytes(fitted) <= left) {
        last.add(fitted);
      }
    }
    break;
  }
  return (kept: [first, ...last.reversed]);
}

String _cut(String text, int most) =>
    text.length <= most ? text : '${text.substring(0, most)}…';

String _cutUtf8(String text, int maxBytes, {bool keepTail = false}) {
  if (utf8.encode(text).length <= maxBytes) return text;
  const ellipsisBytes = 3; // '…' is 3 UTF-8 bytes.
  final limit = maxBytes - ellipsisBytes;
  if (limit <= 0) return '';
  final runes = text.runes.toList();
  var used = 0;
  if (keepTail) {
    var start = runes.length;
    for (var i = runes.length - 1; i >= 0; i--) {
      final b = _runeUtf8Bytes(runes[i]);
      if (used + b > limit) break;
      used += b;
      start = i;
    }
    return '…${String.fromCharCodes(runes.sublist(start))}';
  }
  var end = 0;
  for (var i = 0; i < runes.length; i++) {
    final b = _runeUtf8Bytes(runes[i]);
    if (used + b > limit) break;
    used += b;
    end = i + 1;
  }
  return '${String.fromCharCodes(runes.sublist(0, end))}…';
}

int _runeUtf8Bytes(int rune) => rune <= 0x7F
    ? 1
    : rune <= 0x7FF
    ? 2
    : rune <= 0xFFFF
    ? 3
    : 4;

final _reminders = RegExp(r'<system-reminder>[\s\S]*?(</system-reminder>|$)');

/// [text] without the notes the app adds to what the user writes (each a
/// `<system-reminder>`).
String withoutReminders(String text) {
  if (!text.contains('<system-r')) return text.trim();
  return text.replaceAll(_reminders, '').trim();
}
