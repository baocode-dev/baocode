import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../util/ids.dart';
import '../util/json.dart';

/// The version written on every line, as Claude Code writes its own.
const agentVersion = 'baocode-agent-1.0';

/// A session's conversation, kept as Claude Code keeps its own: one JSON
/// object a line in `<config>/projects/<cwd>/<session>.jsonl`, each message
/// naming the one before it (`parentUuid`), so that a rewind leaves another
/// branch beside the one gone on with, and a compaction a boundary.
///
/// [chain] is the branch the session is on: what the model is sent is
/// made of it ([apiMessages]).
class SessionStore {
  SessionStore({
    required this.sessionId,
    required this.cwd,
    this.file,
    this.gitBranch,
  });

  /// Continues the session kept in [file], on the branch it ended on.
  factory SessionStore.resume({
    required String sessionId,
    required String cwd,
    required String file,
    String? gitBranch,
    bool persist = true,
    bool sidechain = false,
  }) {
    final store = SessionStore(
      sessionId: sessionId,
      cwd: cwd,
      file: persist ? file : null,
      gitBranch: gitBranch,
    );
    store._load(file, sidechain: sidechain);
    return store;
  }

  final String sessionId;
  final String cwd;

  /// Where it is written; null when nothing is kept.
  final String? file;
  String? gitBranch;

  final Map<String, Map<String, Object?>> _byUuid = {};

  /// The branch the session is on, oldest first: messages, compaction
  /// boundaries and how the goal stood.
  final List<Map<String, Object?>> chain = [];

  /// Lines kept beside the conversation (titles), as read.
  final List<Map<String, Object?>> extras = [];

  String? get leaf => chain.isEmpty ? null : chain.last['uuid'] as String?;

  Map<String, Object?>? operator [](String uuid) => _byUuid[uuid];

  bool contains(String uuid) => _byUuid.containsKey(uuid);

  /// Reads [path]: a session's file, or a subagent's ([sidechain]), whose
  /// every message is of its side chain.
  void _load(String path, {bool sidechain = false}) {
    final entries = <Map<String, Object?>>[];
    try {
      for (final line in const LineSplitter().convert(
        File(path).readAsStringSync(),
      )) {
        if (line.trim().isEmpty) continue;
        try {
          final decoded = jsonDecode(line);
          if (decoded is Map) entries.add(decoded.cast<String, Object?>());
        } on FormatException {
          continue;
        }
      }
    } on FileSystemException {
      return;
    }
    for (final entry in entries) {
      if (entry['uuid'] case final String uuid) _byUuid[uuid] = entry;
      if (!_kept(entry)) extras.add(entry);
    }
    Map<String, Object?>? last;
    for (final entry in entries.reversed) {
      if (_kept(entry) &&
          (sidechain || entry['isSidechain'] != true) &&
          entry['uuid'] is String) {
        last = entry;
        break;
      }
    }
    final branch = <Map<String, Object?>>[];
    final seen = <String>{};
    for (var entry = last; entry != null;) {
      final uuid = entry['uuid'] as String;
      if (!seen.add(uuid)) break;
      branch.add(entry);
      final parent =
          (entry['parentUuid'] ?? entry['logicalParentUuid']) as String?;
      entry = parent == null ? null : _byUuid[parent];
    }
    chain.addAll(branch.reversed.where(_kept));
  }

  /// Whether [entry] is part of the conversation (read back), not a line
  /// kept beside it.
  static bool _kept(Map<String, Object?> entry) => switch (entry['type']) {
    'user' || 'assistant' || 'system' => true,
    'attachment' => true,
    _ => false,
  };

  /// Adds [entry] at the end of the branch: its place in it, the session
  /// and the time filled in. Returns it as written.
  Map<String, Object?> append(Map<String, Object?> entry) {
    final full = <String, Object?>{
      'parentUuid': entry.containsKey('parentUuid')
          ? entry['parentUuid']
          : leaf,
      'isSidechain': false,
      'userType': 'external',
      'cwd': cwd,
      'sessionId': sessionId,
      'version': agentVersion,
      'gitBranch': ?gitBranch,
      ...entry,
      'uuid': entry['uuid'] ?? newUuid(),
      'timestamp': entry['timestamp'] ?? _now(),
    };
    _byUuid[full['uuid'] as String] = full;
    chain.add(full);
    _write(full);
    return full;
  }

  /// Keeps [entry] beside the conversation: a title, a snapshot of files.
  void note(Map<String, Object?> entry) {
    final full = {...entry, 'sessionId': sessionId};
    extras.add(full);
    _write(full);
  }

  void _write(Map<String, Object?> entry) {
    final path = file;
    if (path == null) return;
    final out = File(path);
    out.parent.createSync(recursive: true);
    out.writeAsStringSync(
      '${jsonEncode(entry)}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  static String _now() => DateTime.now().toUtc().toIso8601String();

  /// Goes back to before [uuid] (a message of the branch): it and what
  /// followed are left on a branch of their own. Returns whether it was on
  /// the branch.
  bool rewindTo(String uuid) {
    final at = chain.indexWhere((entry) => entry['uuid'] == uuid);
    if (at < 0) return false;
    chain.removeRange(at, chain.length);
    return true;
  }

  /// The user messages of the branch, in order: those the user typed (not
  /// results, notes or summaries).
  Iterable<Map<String, Object?>> get prompts => chain.where(isPrompt);

  static bool isPrompt(Map<String, Object?> entry) {
    if (entry['type'] != 'user' ||
        entry['isMeta'] == true ||
        entry['isCompactSummary'] == true ||
        entry['toolUseResult'] != null) {
      return false;
    }
    final content = asMap(entry['message'])['content'];
    if (content is String) return !content.trimLeft().startsWith('<');
    return asList(content).any(
      (block) =>
          asMap(block)['type'] == 'image' ||
          (asMap(block)['type'] == 'text' &&
              !'${asMap(block)['text']}'.trimLeft().startsWith('<')),
    );
  }

  /// The title the session goes by: the user's, else the one made for it.
  String? get title {
    String? last(String type, String key) {
      for (final entry in extras.reversed) {
        if (entry['type'] == type) return asText(entry[key]);
      }
      return null;
    }

    return last('custom-title', 'customTitle') ?? last('ai-title', 'aiTitle');
  }

  /// What the model is sent: the branch since its last compaction, as
  /// messages the API takes (see [toApiMessages]).
  List<Map<String, Object?>> apiMessages() => toApiMessages(chain);
}

/// [chain] as the Messages API takes it: from the last compaction on; the
/// blocks of one answer (kept a line each) as one message; consecutive
/// messages of one role as one; a call's result first in the message after
/// it, and a result made up for a call left unanswered (an interrupted
/// turn, a crash); empty text left out. The notes kept for the model as
/// system messages are among them when [systemNotes].
List<Map<String, Object?>> toApiMessages(
  List<Map<String, Object?>> chain, {
  bool systemNotes = false,
}) {
  var start = 0;
  for (var i = chain.length - 1; i >= 0; i--) {
    final entry = chain[i];
    if (entry['type'] == 'system' && entry['subtype'] == 'compact_boundary') {
      start = i + 1;
      break;
    }
  }
  final messages = <Map<String, Object?>>[];
  for (final entry in chain.skip(start)) {
    final type = entry['type'];
    if (type == 'attachment' &&
        systemNotes &&
        entry['renderedRole'] == 'system' &&
        messages.isNotEmpty) {
      final text = asString(asMap(entry['attachment'])['text']);
      if (text == null || text.isEmpty) continue;
      final block = {'type': 'text', 'text': text};
      if (messages.last['role'] == 'system') {
        (messages.last['content'] as List<Map<String, Object?>>).add(block);
      } else {
        messages.add({
          'role': 'system',
          'content': [block],
        });
      }
      continue;
    }
    if (type != 'user' && type != 'assistant') continue;
    final message = asMap(entry['message']);
    if (type == 'assistant' && message['model'] == '<synthetic>') continue;
    final blocks = _blocks(message['content']);
    if (blocks.isEmpty) continue;
    final role = type as String;
    if (messages.isNotEmpty && messages.last['role'] == role) {
      final last = messages.last;
      // Another answer's blocks after an answer: one message all the same,
      // as the API holds no two assistant turns in a row.
      (last['content'] as List<Map<String, Object?>>).addAll(blocks);
    } else {
      messages.add({'role': role, 'content': blocks});
    }
  }
  // Each call answered, its result first in the message after it.
  for (var i = 0; i < messages.length; i++) {
    if (messages[i]['role'] != 'assistant') continue;
    final calls = [
      for (final block in messages[i]['content'] as List<Map<String, Object?>>)
        if (block['type'] == 'tool_use') block['id'] as String,
    ];
    if (calls.isEmpty) continue;
    if (i + 1 >= messages.length || messages[i + 1]['role'] != 'user') {
      messages.insert(i + 1, {
        'role': 'user',
        'content': <Map<String, Object?>>[],
      });
    }
    final next = messages[i + 1]['content'] as List<Map<String, Object?>>;
    final results = <Map<String, Object?>>[];
    final others = <Map<String, Object?>>[];
    for (final block in next) {
      if (block['type'] == 'tool_result') {
        // A result for a call of this answer; one for none would be refused.
        if (calls.contains(block['tool_use_id'])) results.add(block);
      } else {
        others.add(block);
      }
    }
    final answered = {for (final r in results) r['tool_use_id']};
    for (final call in calls) {
      if (!answered.contains(call)) {
        results.add({
          'type': 'tool_result',
          'tool_use_id': call,
          'content': '[Tool call interrupted: no result]',
          'is_error': true,
        });
      }
    }
    // In the order of the calls.
    results.sort(
      (a, b) =>
          calls.indexOf(a['tool_use_id'] as String) -
          calls.indexOf(b['tool_use_id'] as String),
    );
    next
      ..clear()
      ..addAll([...results, ...others]);
  }
  // Results of calls not in the answer before them (that answer cut off):
  // left out.
  for (var i = 0; i < messages.length; i++) {
    if (messages[i]['role'] != 'user') continue;
    final before = i > 0 ? messages[i - 1] : null;
    final calls = {
      if (before != null)
        for (final block in before['content'] as List<Map<String, Object?>>)
          if (block['type'] == 'tool_use') block['id'],
    };
    (messages[i]['content'] as List<Map<String, Object?>>).removeWhere(
      (block) =>
          block['type'] == 'tool_result' &&
          !calls.contains(block['tool_use_id']),
    );
  }
  messages.removeWhere((m) => (m['content'] as List).isEmpty);
  // The conversation starts with the user.
  while (messages.isNotEmpty && messages.first['role'] != 'user') {
    messages.removeAt(0);
  }
  return messages;
}

List<Map<String, Object?>> _blocks(Object? content) {
  if (content is String) {
    return content.trim().isEmpty
        ? []
        : [
            {'type': 'text', 'text': content},
          ];
  }
  return [
    for (final raw in asList(content))
      if (raw is Map)
        if (_keep(raw.cast<String, Object?>()))
          _clean(raw.cast<String, Object?>()),
  ];
}

bool _keep(Map<String, Object?> block) => switch (block['type']) {
  'text' => '${block['text'] ?? ''}'.trim().isNotEmpty,
  'thinking' || 'redacted_thinking' => true,
  'tool_use' || 'tool_result' || 'image' || 'document' => true,
  'server_tool_use' || 'web_search_tool_result' => true,
  _ => false,
};

/// [block] as sent: without what was kept of it for the transcript only.
Map<String, Object?> _clean(Map<String, Object?> block) {
  final copy = {...block};
  copy.remove('cache_control');
  if (copy['type'] == 'tool_result' && copy['content'] is List) {
    copy['content'] = [
      for (final part in asList(copy['content']))
        if (part is Map &&
            (part['type'] != 'text' || '${part['text'] ?? ''}'.isNotEmpty))
          part,
    ];
    if ((copy['content'] as List).isEmpty) copy['content'] = '';
  }
  return copy;
}

/// The file of a subagent's conversation, beside its session's.
String sidechainFile(String sessionFile, String agentId) => p.join(
  p.dirname(sessionFile),
  p.basenameWithoutExtension(sessionFile),
  'subagents',
  'agent-$agentId.jsonl',
);
