import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../../platform/app_paths.dart';
import '../../platform/data_dir.dart';
import '../agent_kernel.dart';
import 'claude_environment.dart';

/// Claude Code's own record of its sessions: one JSON-lines file per
/// session under `<config>/projects/<cwd, dashed>/`.
class ClaudeStorage implements SessionCatalog {
  const ClaudeStorage({this.configDir, this.tempDir, this.cacheFile});

  /// Where Claude Code keeps its state; by default `BAOCODE_CLAUDE_DATA_PATH`
  /// as the login shell has it, else `CLAUDE_CONFIG_DIR`, else
  /// `<home>/.claude`.
  final String? configDir;

  /// Where it keeps what a session's tasks print (`claude-<uid>/`); the
  /// system's temporary folder by default (`/tmp` where that is where the
  /// CLI puts them, see [AppPaths.tempDir]).
  final String? tempDir;

  /// Where what was made of each session file is kept between runs (see
  /// [_SummaryCache]); in the app's cache folder by default.
  final String? cacheFile;

  Future<String> _config() async =>
      configDir ?? await ClaudeEnvironment.configDir();

  @override
  Future<void> delete(String id) async {
    // A session id names files and directories: nothing else may pass.
    if (!RegExp(r'^[0-9a-zA-Z][0-9a-zA-Z_-]*$').hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'not a session id');
    }
    final config = await _config();
    final temp = tempDir ?? AppPaths.tempDir;
    return Isolate.run(() => _delete(id, config, temp));
  }

  @override
  Future<List<ProjectRecord>> projects() async {
    final root = '${await _config()}/projects';
    final cache =
        cacheFile ??
        p.join(DataDirectory.current.cacheDir, 'claude-sessions.json');
    return Isolate.run(() => _scan(root, cache));
  }

  @override
  Future<List<SessionRecord>> sessionsIn(String cwd) async {
    final all = await projects();
    return all.where((p) => p.path == cwd).firstOrNull?.sessions ?? const [];
  }

  /// The session's conversation along the branch it ended on.
  static Future<List<Map<String, Object?>>> read(SessionRecord session) {
    final path = session.path;
    if (path == null) return Future.value(const []);
    return Isolate.run(() => _branch(path));
  }
}

/// Removes the session [id]: its conversation and what is kept beside it
/// (subagent logs, file checkpoints, environment, task output). Whatever
/// is already gone is skipped.
void _delete(String id, String config, String temp) {
  List<Directory> dirs(String path) {
    final dir = Directory(path);
    return dir.existsSync()
        ? dir.listSync().whereType<Directory>().toList()
        : [];
  }

  final doomed = <FileSystemEntity>[
    Directory('$config/file-history/$id'),
    Directory('$config/session-env/$id'),
    // Under the project it ran in, whichever that was.
    for (final project in dirs('$config/projects')) ...[
      File('${project.path}/$id.jsonl'),
      Directory('${project.path}/$id'),
    ],
    for (final user in dirs(temp))
      if (p.basename(user.path).startsWith('claude-'))
        for (final project in dirs(user.path)) Directory('${project.path}/$id'),
  ];
  for (final entity in doomed) {
    if (!entity.existsSync()) continue;
    try {
      entity.deleteSync(recursive: true);
    } on FileSystemException {
      // Gone meanwhile.
    }
  }
}

List<ProjectRecord> _scan(String root, String cachePath) {
  final dir = Directory(root);
  if (!dir.existsSync()) return const [];
  final cache = _SummaryCache.load(cachePath, root);
  final byCwd = <String, List<SessionRecord>>{};
  for (final project in dir.listSync().whereType<Directory>()) {
    for (final file in project.listSync().whereType<File>()) {
      if (!file.path.endsWith('.jsonl')) continue;
      final session = cache.summarize(file);
      if (session == null) continue;
      (byCwd[session.cwd] ??= []).add(session);
    }
  }
  cache.save();
  final projects = [
    for (final MapEntry(key: cwd, value: sessions) in byCwd.entries)
      if (Directory(cwd).existsSync())
        ProjectRecord(
          path: cwd,
          sessions: sessions
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
        ),
  ]..sort((a, b) => b.updatedAt!.compareTo(a.updatedAt!));
  return projects;
}

/// What [_summarize] made of each session file, kept between runs: reading
/// them all again is what made the first listing slow. A file is read again
/// only once its size or time of change differs; only the files still there
/// are kept, so it stays a few hundred bytes a session. Anything amiss with
/// it (unreadable, another version, another folder) and it starts over.
class _SummaryCache {
  _SummaryCache._(this._path, this._root, this._old);

  /// Raise it whenever [_summarize] makes something else of a file.
  static const _version = 1;

  factory _SummaryCache.load(String path, String root) {
    var old = const <String, Object?>{};
    try {
      final json = jsonDecode(File(path).readAsStringSync());
      if (json
          case {
            'version': _version,
            'root': final String kept,
            'files': final Map<String, Object?> files,
          }
          when kept == root) {
        old = files;
      }
    } on Object {
      // None yet, or not one to trust.
    }
    return _SummaryCache._(path, root, old);
  }

  final String _path;
  final String _root;
  final Map<String, Object?> _old;
  final Map<String, Object?> _fresh = {};
  bool _changed = false;

  SessionRecord? summarize(File file) {
    final stat = file.statSync();
    if (stat.type == FileSystemEntityType.notFound) return null;
    final size = stat.size;
    final modified = stat.modified.microsecondsSinceEpoch;
    if (_old[file.path]
        case {
          'size': final int keptSize,
          'modified': final int keptModified,
          'session': final Object? kept,
        }
        when keptSize == size && keptModified == modified) {
      final session = _decode(file.path, kept);
      if (session != null || kept == null) {
        _fresh[file.path] = _old[file.path];
        return session;
      }
    }
    // Stat before reading: a write meanwhile shows as a change next time.
    final session = _summarize(file);
    _fresh[file.path] = {
      'size': size,
      'modified': modified,
      'session': session == null
          ? null
          : {
              'title': session.title,
              'cwd': session.cwd,
              'updatedAt': session.updatedAt.microsecondsSinceEpoch,
            },
    };
    _changed = true;
    return session;
  }

  static SessionRecord? _decode(String path, Object? kept) {
    if (kept case {
      'title': final String title,
      'cwd': final String cwd,
      'updatedAt': final int updatedAt,
    }) {
      final name = p.basename(path);
      return SessionRecord(
        id: name.substring(0, name.length - '.jsonl'.length),
        title: title,
        updatedAt: DateTime.fromMicrosecondsSinceEpoch(updatedAt),
        cwd: cwd,
        path: path,
      );
    }
    return null;
  }

  /// Writes it, if anything changed: whole, so a run cut short leaves the
  /// old one rather than half of a new one.
  void save() {
    if (!_changed && _fresh.length == _old.length) return;
    // Its own: two listings may save at once.
    final temp = File('$_path.$pid.${DateTime.now().microsecondsSinceEpoch}');
    try {
      temp.parent.createSync(recursive: true);
      temp.writeAsStringSync(
        jsonEncode({'version': _version, 'root': _root, 'files': _fresh}),
      );
      temp.renameSync(_path);
    } on Object {
      // Read again next time.
      try {
        if (temp.existsSync()) temp.deleteSync();
      } on Object {
        // Left for the next save to overwrite.
      }
    }
  }
}

/// Title, place and time of a session file; null for one with no
/// conversation (e.g. only a failed start). Raise [_SummaryCache._version]
/// when changing what it makes of a file.
SessionRecord? _summarize(File file) {
  final String text;
  try {
    text = file.readAsStringSync();
  } on Object {
    return null;
  }
  String? cwd;
  String? firstPrompt;
  // The last title wins; scan for the marker rather than decoding every
  // line of a long session.
  String? lastTitle(String type, String key) {
    final at = text.lastIndexOf('"type":"$type"');
    if (at < 0) return null;
    final start = text.lastIndexOf('\n', at) + 1;
    final end = text.indexOf('\n', at);
    final line = text.substring(start, end < 0 ? text.length : end);
    try {
      final title = ((jsonDecode(line) as Map)[key] as String?)?.trim();
      return title?.isEmpty ?? true ? null : title;
    } on Object {
      return null;
    }
  }

  // The user's (`/rename`) before the one Claude Code generated.
  final title =
      lastTitle('custom-title', 'customTitle') ??
      lastTitle('ai-title', 'aiTitle');
  final lines = const LineSplitter().convert(text);
  for (final line in lines) {
    if (!line.contains('"type":"user"')) continue;
    final Map<String, Object?> entry;
    try {
      entry = (jsonDecode(line) as Map).cast<String, Object?>();
    } on Object {
      continue;
    }
    cwd ??= entry['cwd'] as String?;
    if (entry['isSidechain'] == true || entry['isMeta'] == true) continue;
    final prompt = _promptText(entry);
    if (prompt != null) {
      firstPrompt = prompt;
      break;
    }
  }
  if (cwd == null || firstPrompt == null) return null;
  final name = file.uri.pathSegments.last;
  final firstLine = firstPrompt.trim().split('\n').first;
  return SessionRecord(
    id: name.substring(0, name.length - '.jsonl'.length),
    title:
        title ??
        (firstLine.length > 120
            ? '${firstLine.substring(0, 120)}…'
            : firstLine),
    // When it was last talked in: the file is written to besides (titles,
    // the last prompt), by the CLI resuming it too.
    updatedAt: _lastMessageTime(lines) ?? file.lastModifiedSync(),
    cwd: cwd,
    path: file.path,
  );
}

/// What the user typed, or null for a tool result, command wrapper or
/// injected note.
/// The time of the last message, user's or Claude's, in [lines]; null
/// when none has one.
DateTime? _lastMessageTime(List<String> lines) {
  for (final line in lines.reversed) {
    if (!line.contains('"timestamp"')) continue;
    if (!line.contains('"type":"user"') &&
        !line.contains('"type":"assistant"')) {
      continue;
    }
    try {
      final entry = jsonDecode(line) as Map;
      if (entry['type'] != 'user' && entry['type'] != 'assistant') continue;
      if (entry['timestamp'] case final String time) {
        if (DateTime.tryParse(time) case final parsed?) return parsed.toLocal();
      }
    } on Object {
      continue;
    }
  }
  return null;
}

/// The text of a message the user typed: empty for images alone, null for
/// none (a command's output, an interruption).
String? _promptText(Map<String, Object?> entry) {
  final message = entry['message'];
  if (message is! Map) return null;
  final content = message['content'];
  final blocks = content is List<Object?> ? content : const <Object?>[];
  final text = switch (content) {
    final String text => text,
    _ => [
      for (final block in blocks)
        // Not the name the CLI gives an image ahead of it (`[Image #1]`).
        if (block is Map &&
            block['type'] == 'text' &&
            !_imageName.hasMatch(block['text'] as String? ?? ''))
          block['text'],
    ].join('\n'),
  };
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    final images = blocks.any((b) => b is Map && b['type'] == 'image');
    return images ? '' : null;
  }
  if (trimmed.startsWith('<')) return null;
  if (trimmed.startsWith('[Request interrupted')) return null;
  return trimmed;
}

/// A text block that is only an image's name, as the CLI puts ahead of it.
final _imageName = RegExp(r'^\s*\[Image #\d+\]\s*$');

/// The conversation, oldest first, along the branch that ends with the
/// last message: rewinds and forks leave other branches in the file.
List<Map<String, Object?>> _branch(String path) {
  final entries = <Map<String, Object?>>[];
  for (final line in const LineSplitter().convert(
    File(path).readAsStringSync(),
  )) {
    if (line.isEmpty) continue;
    try {
      entries.add((jsonDecode(line) as Map).cast<String, Object?>());
    } on Object {
      continue;
    }
  }
  final byId = <String, Map<String, Object?>>{
    for (final entry in entries)
      if (entry['uuid'] case final String id) id: entry,
  };
  Map<String, Object?>? leaf;
  for (final entry in entries.reversed) {
    final type = entry['type'];
    if ((type == 'user' || type == 'assistant' || type == 'system') &&
        entry['isSidechain'] != true &&
        entry['uuid'] is String) {
      leaf = entry;
      break;
    }
  }
  final branch = <Map<String, Object?>>[];
  final seen = <String>{};
  for (var entry = leaf; entry != null;) {
    final id = entry['uuid'] as String;
    if (!seen.add(id)) break;
    branch.add(entry);
    final parent =
        (entry['parentUuid'] ?? entry['logicalParentUuid']) as String?;
    entry = parent == null ? null : byId[parent];
  }
  return [
    for (final entry in branch.reversed)
      if (entry['type'] == 'user' ||
          entry['type'] == 'assistant' ||
          entry['type'] == 'system')
        entry,
  ];
}
