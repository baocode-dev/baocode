import 'dart:io';
import 'dart:isolate';

import 'package:bao_remote/local.dart' show SessionIndexStore;
import 'package:path/path.dart' as p;

import '../kernel/claude_code/claude_environment.dart';
import '../platform/data_dir.dart';
import 'conversation_search.dart';

/// Searches the sessions Claude Code keeps (`<config>/projects/*/*.jsonl`):
/// backed by [SessionIndexStore]'s incremental persisted turn index so
/// restarts and appended messages avoid re-reading multi-MB `.jsonl` files.
class ClaudeConversationSearch implements ConversationSearch {
  ClaudeConversationSearch({this.configDir, this.indexDir});

  /// Claude Code's config folder; by default as its kernel finds it.
  final String? configDir;

  /// Directory where `.idx.gz` sidecar indexes are persisted; defaults to
  /// `<cacheDir>/session-index` when [configDir] is null (production), and
  /// null when a custom [configDir] is passed without [indexDir] (tests).
  final String? indexDir;

  final Map<String, _Kept> _kept = {};
  Future<void>? _preparing;

  String? get _resolvedIndexDir =>
      indexDir ??
      (configDir == null
          ? p.join(DataDirectory.current.cacheDir, 'session-index')
          : null);

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
    final dir = _resolvedIndexDir;
    final read = await Isolate.run(() => _readChanged(root, known, dir));
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

/// The session files under [root], and the searchable text of those whose
/// size or modification time differs from [known], read via
/// [SessionIndexStore] so unchanged or appended files skip full re-scans.
_Read _readChanged(
  String root,
  Map<String, ({int size, int modified})> known,
  String? indexDir,
) {
  final present = <String>{};
  final changed = <({String path, int size, int modified, String text})>[];
  final dir = Directory(root);
  if (!dir.existsSync()) return (present: present, changed: changed);
  final store = SessionIndexStore(cacheDir: indexDir);
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
      String text;
      try {
        final index = store.openSync(
          file.path,
          fileSize: size,
          fileModified: modified,
        );
        text = index.searchableText();
      } on Object {
        text = '';
      }
      changed.add((path: file.path, size: size, modified: modified, text: text));
    }
  }
  return (present: present, changed: changed);
}
