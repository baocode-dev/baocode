import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../kernel/claude_code/claude_environment.dart';
import 'conversation_search.dart';

/// Searches the sessions Claude Code keeps (`<config>/projects/*/*.jsonl`):
/// what the user and Claude said in each, read once and kept in memory
/// until its file changes.
class ClaudeConversationSearch implements ConversationSearch {
  ClaudeConversationSearch({this.configDir});

  /// Claude Code's config folder; by default as its kernel finds it.
  final String? configDir;

  final Map<String, _Kept> _kept = {};
  Future<void>? _preparing;

  @override
  Future<void> prepare() =>
      _preparing ??= _prepare().whenComplete(() => _preparing = null);

  Future<void> _prepare() async {
    final root = p.join(
      configDir ?? await ClaudeEnvironment.configDir(),
      'projects',
    );
    final known = {
      for (final MapEntry(:key, :value) in _kept.entries)
        key: (size: value.size, modified: value.modified),
    };
    final read = await Isolate.run(() => _readChanged(root, known));
    _kept.removeWhere((path, _) => !read.present.contains(path));
    for (final session in read.changed) {
      _kept[session.path] = _Kept(
        session.size,
        session.modified,
        session.text,
        session.text.toLowerCase(),
      );
    }
  }

  @override
  Future<List<ConversationHit>> search(String query, {int limit = 50}) async {
    await prepare();
    final needle = query.trim();
    if (needle.isEmpty) return const [];
    final sessions = _kept.entries.toList()
      ..sort((a, b) => b.value.modified.compareTo(a.value.modified));
    final hits = <ConversationHit>[];
    for (final MapEntry(key: path, value: kept) in sessions) {
      final name = p.basename(path);
      final id = name.substring(0, name.length - '.jsonl'.length);
      final hit = findIn(id, kept.text, needle, lower: kept.lower);
      if (hit == null) continue;
      hits.add(hit);
      if (hits.length >= limit) break;
    }
    return hits;
  }
}

class _Kept {
  _Kept(this.size, this.modified, this.text, this.lower);

  final int size;
  final int modified;
  final String text;
  final String lower;
}

typedef _Read = ({
  Set<String> present,
  List<({String path, int size, int modified, String text})> changed,
});

/// The session files under [root], and the text of those not as [known]
/// had them.
_Read _readChanged(String root, Map<String, ({int size, int modified})> known) {
  final present = <String>{};
  final changed = <({String path, int size, int modified, String text})>[];
  final dir = Directory(root);
  if (!dir.existsSync()) return (present: present, changed: changed);
  for (final project in dir.listSync().whereType<Directory>()) {
    for (final file in project.listSync().whereType<File>()) {
      if (!file.path.endsWith('.jsonl')) continue;
      final stat = file.statSync();
      final size = stat.size;
      final modified = stat.modified.microsecondsSinceEpoch;
      present.add(file.path);
      final was = known[file.path];
      if (was != null && was.size == size && was.modified == modified) {
        continue;
      }
      changed.add((
        path: file.path,
        size: size,
        modified: modified,
        text: _conversationText(file),
      ));
    }
  }
  return (present: present, changed: changed);
}

/// What the user typed and Claude answered, a message a line or more:
/// not tools' input or output, thoughts, subagents' or injected notes.
String _conversationText(File file) {
  final String text;
  try {
    text = file.readAsStringSync();
  } on Object {
    return '';
  }
  final buffer = StringBuffer();
  for (final line in const LineSplitter().convert(text)) {
    if (!line.contains('"type":"user"') &&
        !line.contains('"type":"assistant"')) {
      continue;
    }
    final Object? entry;
    try {
      entry = jsonDecode(line);
    } on Object {
      continue;
    }
    if (entry is! Map<String, Object?>) continue;
    if (entry['isSidechain'] == true || entry['isMeta'] == true) continue;
    final type = entry['type'];
    if (type != 'user' && type != 'assistant') continue;
    final message = entry['message'];
    if (message is! Map<String, Object?>) continue;
    final content = message['content'];
    final parts = switch (content) {
      final String text => [text],
      final List<Object?> blocks => [
        for (final block in blocks)
          if (block is Map<String, Object?> &&
              block['type'] == 'text' &&
              block['text'] is String)
            block['text']! as String,
      ],
      _ => const <String>[],
    };
    for (final part in parts) {
      final trimmed = part.trim();
      // Command wrappers and the CLI's own notes, not what was said.
      if (trimmed.isEmpty || type == 'user' && trimmed.startsWith('<')) {
        continue;
      }
      buffer.writeln(trimmed);
    }
  }
  return buffer.toString();
}
