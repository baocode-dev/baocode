import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../agent_kernel.dart';
import 'claude_environment.dart';

/// Claude Code's own record of its sessions: one JSON-lines file per
/// session under `<config>/projects/<cwd, dashed>/`.
class ClaudeStorage implements SessionCatalog {
  const ClaudeStorage({this.configDir, this.tempDir = '/tmp'});

  /// Where Claude Code keeps its state; by default `MONAD_CLAUDE_DATA_PATH`
  /// as the login shell has it, else `CLAUDE_CONFIG_DIR`, else
  /// `<home>/.claude`.
  final String? configDir;

  /// Where it keeps what a session's tasks print (`claude-<uid>/`).
  final String tempDir;

  Future<String> _config() async =>
      configDir ?? await ClaudeEnvironment.configDir();

  @override
  Future<void> delete(String id) async {
    // A session id names files and directories: nothing else may pass.
    if (!RegExp(r'^[0-9a-zA-Z][0-9a-zA-Z_-]*$').hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'not a session id');
    }
    final config = await _config();
    final temp = tempDir;
    return Isolate.run(() => _delete(id, config, temp));
  }

  @override
  Future<List<ProjectRecord>> projects() async {
    final root = '${await _config()}/projects';
    return Isolate.run(() => _scan(root));
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
      if (user.path.split('/').last.startsWith('claude-'))
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

List<ProjectRecord> _scan(String root) {
  final dir = Directory(root);
  if (!dir.existsSync()) return const [];
  final byCwd = <String, List<SessionRecord>>{};
  for (final project in dir.listSync().whereType<Directory>()) {
    for (final file in project.listSync().whereType<File>()) {
      if (!file.path.endsWith('.jsonl')) continue;
      final session = _summarize(file);
      if (session == null) continue;
      (byCwd[session.cwd] ??= []).add(session);
    }
  }
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

/// Title, place and time of a session file; null for one with no
/// conversation (e.g. only a failed start).
SessionRecord? _summarize(File file) {
  final String text;
  try {
    text = file.readAsStringSync();
  } on Object {
    return null;
  }
  String? cwd;
  String? firstPrompt;
  String? title;
  // The last title wins; scan for the marker rather than decoding every
  // line of a long session.
  final titleAt = text.lastIndexOf('"type":"custom-title"');
  if (titleAt >= 0) {
    final start = text.lastIndexOf('\n', titleAt) + 1;
    final end = text.indexOf('\n', titleAt);
    final line = text.substring(start, end < 0 ? text.length : end);
    try {
      title = (jsonDecode(line) as Map)['customTitle'] as String?;
    } on Object {
      title = null;
    }
  }
  for (final line in const LineSplitter().convert(text)) {
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
    title: (title?.trim().isNotEmpty ?? false)
        ? title!.trim()
        : firstLine.length > 120
        ? '${firstLine.substring(0, 120)}…'
        : firstLine,
    updatedAt: file.lastModifiedSync(),
    cwd: cwd,
    path: file.path,
  );
}

/// What the user typed, or null for a tool result, command wrapper or
/// injected note.
String? _promptText(Map<String, Object?> entry) {
  final message = entry['message'];
  if (message is! Map) return null;
  final content = message['content'];
  final text = switch (content) {
    final String text => text,
    final List<Object?> blocks => [
      for (final block in blocks)
        if (block is Map && block['type'] == 'text') block['text'],
    ].join('\n'),
    _ => '',
  };
  final trimmed = text.trim();
  if (trimmed.isEmpty || trimmed.startsWith('<')) return null;
  if (trimmed.startsWith('[Request interrupted')) return null;
  return trimmed;
}

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
