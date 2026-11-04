import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bao_agent/bao_agent.dart' show AgentPaths;
import 'package:path/path.dart' as p;

import '../platform/app_paths.dart';
import 'claude_environment.dart';
import 'claude_history_page.dart';

/// A session Claude Code kept: its title, the folder it ran in, and when
/// it was last talked in.
class ClaudeSessionSummary {
  const ClaudeSessionSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.cwd,
    required this.path,
  });

  factory ClaudeSessionSummary.fromJson(Map<String, Object?> json) =>
      ClaudeSessionSummary(
        id: json['id'] as String,
        title: json['title'] as String,
        updatedAt: DateTime.fromMicrosecondsSinceEpoch(
          json['updatedAt'] as int,
        ),
        cwd: json['cwd'] as String,
        path: json['path'] as String,
      );

  final String id;

  /// Empty when it was first asked something with images alone, and not
  /// named since.
  final String title;
  final DateTime updatedAt;

  /// The project directory it ran in.
  final String cwd;

  /// Its JSON-lines file.
  final String path;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'updatedAt': updatedAt.microsecondsSinceEpoch,
    'cwd': cwd,
    'path': path,
  };
}

/// A project directory and its sessions, newest first.
class ClaudeProjectSummary {
  const ClaudeProjectSummary({required this.path, required this.sessions});

  factory ClaudeProjectSummary.fromJson(Map<String, Object?> json) =>
      ClaudeProjectSummary(
        path: json['path'] as String,
        sessions: [
          for (final session in json['sessions'] as List)
            ClaudeSessionSummary.fromJson(
              (session as Map).cast<String, Object?>(),
            ),
        ],
      );

  final String path;
  final List<ClaudeSessionSummary> sessions;

  DateTime? get updatedAt => sessions.isEmpty ? null : sessions.first.updatedAt;

  Map<String, Object?> toJson() => {
    'path': path,
    'sessions': [for (final session in sessions) session.toJson()],
  };
}

/// Claude Code's own record of its sessions: one JSON-lines file per
/// session under `<config>/projects/<cwd, dashed>/`.
class ClaudeSessions {
  const ClaudeSessions({required this.cacheFile, this.configDir, this.tempDir});

  /// Where Claude Code keeps its state; by default `BAOCODE_CLAUDE_DATA_PATH`
  /// as the login shell has it, else `CLAUDE_CONFIG_DIR`, else
  /// `<home>/.claude`.
  final String? configDir;

  /// Where it keeps what a session's tasks print (`claude-<uid>/`); the
  /// system's temporary folder by default (`/tmp` where that is where the
  /// CLI puts them, see [AppPaths.tempDir]).
  final String? tempDir;

  /// Where what was made of each session file is kept between runs (see
  /// [_SummaryCache]).
  final String cacheFile;

  Future<String> _config() async =>
      configDir ?? await ClaudeEnvironment.configDir();

  /// A session id names files and directories: nothing else may pass.
  static void _checkId(String id) {
    if (!RegExp(r'^[0-9a-zA-Z][0-9a-zA-Z_-]*$').hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'not a session id');
    }
  }

  /// Deletes the session [id] and everything kept with it, for good.
  Future<void> delete(String id) async {
    _checkId(id);
    final config = await _config();
    final temp = tempDir ?? AppPaths.tempDir;
    return Isolate.run(() => _delete(id, config, temp));
  }

  /// The projects with sessions, the most recently talked in first.
  Future<List<ClaudeProjectSummary>> projects() async {
    final root = '${await _config()}/projects';
    final cache = cacheFile;
    return Isolate.run(() => _scan(root, cache));
  }

  /// The session's conversation along the branch it ended on.
  static Future<List<Map<String, Object?>>> read(String path) =>
      Isolate.run(() => _branch(path));

  /// The last [turns] of the session's conversation, along the branch it
  /// ended on; or the [turns] before the line [before] (see
  /// [ClaudeHistoryPage.earlier]). A long one is shown sooner so, from a
  /// remote project's host above all.
  ///
  /// Fewer once they come to some [bytes]: a turn the agent worked long
  /// at may be most of the session.
  static Future<ClaudeHistoryPage> readPage(
    String path, {
    required int turns,
    String? before,
    int bytes = pageBytes,
  }) async {
    final kept = _linesKept[path];
    final (lines, page) = await Isolate.run(() {
      final file = File(path).openSync();
      try {
        final lines =
            (kept == null ? null : _Lines.readOn(file, kept)) ??
            _Lines.readOn(file, null)!;
        final branch = _Branch(file, lines);
        return (
          lines,
          _page(branch, turns: turns, before: before, bytes: bytes),
        );
      } finally {
        file.closeSync();
      }
    });
    _linesKept
      ..remove(path)
      ..[path] = lines;
    if (_linesKept.length > 8) _linesKept.remove(_linesKept.keys.first);
    return page;
  }

  /// The lines of the sessions whose pages were read last (see [_Lines]).
  static final _linesKept = <String, _Lines>{};

  /// How much a page of [readPage] comes to, about.
  static const pageBytes = 512 * 1024;

  /// What the session [id] kept of its goal (`/goal`): its `goal_status`
  /// lines, as they are, in the order written. Empty with none, or no such
  /// session yet.
  Future<List<Map<String, Object?>>> goal(String id) async {
    _checkId(id);
    final config = await _config();
    return Isolate.run(() => _goal(id, config));
  }

  /// Copies the session [id] into a new one, [into], beside it: its
  /// conversation along the branch it ended on, without the user message
  /// [before] (by its uuid) and what follows, when given; titled [title].
  /// Claude Code resumes it as it would the original there. Returns the new
  /// session's file.
  Future<String> fork(
    String id,
    String into, {
    String? before,
    String? title,
  }) async {
    _checkId(id);
    _checkId(into);
    final config = await _config();
    return Isolate.run(() => _fork(id, into, config, before, title));
  }

  /// Has the sessions that ran in [from] run in [to] (a project's folder
  /// moved, or the project pointed elsewhere): their files go to [to]'s
  /// folder of sessions, the folder they name rewritten, with what is kept
  /// beside them and the project's memory. Claude Code lists and resumes
  /// them there from then on. Returns how many moved.
  Future<int> move(String from, String to) async {
    final config = await _config();
    return Isolate.run(() => _move(from, to, config));
  }
}

/// Moves the sessions of [from] to [to] (see [ClaudeSessions.move]).
int _move(String from, String to, String config) {
  final projects = '$config/projects';
  final source = Directory(p.join(projects, AgentPaths.projectDirName(from)));
  if (!source.existsSync() || p.equals(from, to)) return 0;
  final target = Directory(p.join(projects, AgentPaths.projectDirName(to)))
    ..createSync(recursive: true);
  final same = p.equals(source.path, target.path);
  var moved = 0;
  for (final file in source.listSync().whereType<File>()) {
    if (!file.path.endsWith('.jsonl')) continue;
    final text = file.readAsStringSync();
    // Another folder's, dashed alike (`a-b` and `a/b`).
    if (_cwdOf(text) case final cwd? when !p.equals(cwd, from)) continue;
    final name = p.basename(file.path);
    final out = File(p.join(target.path, name));
    if (!same && out.existsSync()) continue;
    // Whole or not at all, as a fork is.
    final temp = File('${out.path}.$pid.tmp')
      ..writeAsStringSync(_relocate(text, from, to), flush: true);
    temp.renameSync(out.path);
    if (!same) {
      file.deleteSync();
      // Its subagents' logs and tools' output.
      final beside = Directory(p.withoutExtension(file.path));
      final there = p.join(target.path, p.basename(beside.path));
      if (beside.existsSync() && !Directory(there).existsSync()) {
        beside.renameSync(there);
      }
    }
    moved++;
  }
  if (same) return moved;
  final memory = Directory(p.join(source.path, 'memory'));
  final memoryThere = p.join(target.path, 'memory');
  if (memory.existsSync() && !Directory(memoryThere).existsSync()) {
    memory.renameSync(memoryThere);
  }
  if (source.listSync().isEmpty) source.deleteSync();
  return moved;
}

/// The folder a session file says it ran in: its first line that names
/// one's.
String? _cwdOf(String text) {
  for (final line in const LineSplitter().convert(text)) {
    if (!line.contains('"cwd"')) continue;
    if (_decode(line)?['cwd'] case final String cwd) return cwd;
  }
  return null;
}

/// [text], a session's lines, with the folders in [from] in [to] instead:
/// only the lines that name one rewritten, the rest as they were.
String _relocate(String text, String from, String to) {
  final out = StringBuffer();
  for (final line in const LineSplitter().convert(text)) {
    final entry = line.contains('"cwd"') ? _decode(line) : null;
    final cwd = entry?['cwd'];
    if (cwd is String && (p.equals(cwd, from) || p.isWithin(from, cwd))) {
      out.writeln(
        jsonEncode({
          ...entry!,
          'cwd': p.equals(cwd, from)
              ? to
              : p.join(to, p.relative(cwd, from: from)),
        }),
      );
    } else {
      out.writeln(line);
    }
  }
  return out.toString();
}

/// Writes the session [into] as a copy of [id] (see [ClaudeSessions.fork]).
String _fork(
  String id,
  String into,
  String config,
  String? before,
  String? title,
) {
  final projects = Directory('$config/projects');
  final file = projects.existsSync()
      ? projects
            .listSync()
            .whereType<Directory>()
            .map((project) => File('${project.path}/$id.jsonl'))
            .where((file) => file.existsSync())
            .firstOrNull
      : null;
  if (file == null) throw StateError('No session $id');
  final entries = [
    for (final line in const LineSplitter().convert(file.readAsStringSync()))
      ?_decode(line),
  ];
  final byId = <String, Map<String, Object?>>{
    for (final entry in entries)
      if (entry['uuid'] case final String uuid) uuid: entry,
  };
  String? parentOf(Map<String, Object?> entry) =>
      (entry['parentUuid'] ?? entry['logicalParentUuid']) as String?;
  final Map<String, Object?>? leaf;
  if (before != null) {
    final cut = byId[before];
    if (cut == null) throw StateError('No message $before in session $id');
    leaf = switch (parentOf(cut)) {
      final parent? => byId[parent],
      null => null,
    };
  } else {
    leaf = entries.reversed
        .where(
          (e) => _kept(e) && e['isSidechain'] != true && e['uuid'] is String,
        )
        .firstOrNull;
  }
  // The chain to it, every line of it as written (attachments, compaction
  // boundaries): what the CLI makes of the original, it makes of this.
  final chain = <Map<String, Object?>>[];
  final seen = <String>{};
  for (var entry = leaf; entry != null;) {
    if (!seen.add(entry['uuid'] as String)) break;
    chain.add(entry);
    entry = switch (parentOf(entry)) {
      final parent? => byId[parent],
      null => null,
    };
  }
  if (chain.isEmpty) throw StateError('Nothing to fork in session $id');
  final out = StringBuffer();
  for (final entry in chain.reversed) {
    out.writeln(jsonEncode({...entry, 'sessionId': into}));
  }
  if (title != null && title.trim().isNotEmpty) {
    out.writeln(
      jsonEncode({
        'type': 'custom-title',
        'customTitle': title.trim(),
        'sessionId': into,
      }),
    );
  }
  final forked = File('${file.parent.path}/$into.jsonl');
  // Whole or not at all: a half-written one would resume as a broken
  // conversation.
  final temp = File('${forked.path}.$pid.tmp');
  temp.writeAsStringSync(out.toString(), flush: true);
  temp.renameSync(forked.path);
  return forked.path;
}

/// The `goal_status` lines of the session [id], wherever its project is.
List<Map<String, Object?>> _goal(String id, String config) {
  final projects = Directory('$config/projects');
  if (!projects.existsSync()) return const [];
  for (final project in projects.listSync().whereType<Directory>()) {
    final file = File('${project.path}/$id.jsonl');
    if (!file.existsSync()) continue;
    return [
      // Most lines are not: only these are decoded. Asked again as each
      // turn ends, of a session that may be hundreds of MB: looked for in
      // its bytes, not its text.
      for (final line in _linesWith(file.readAsBytesSync(), _goalStatus))
        if (_decode(line) case final entry?
            when entry['type'] == 'attachment' &&
                entry['attachment'] is Map &&
                (entry['attachment'] as Map)['type'] == 'goal_status')
          entry,
    ];
  }
  return const [];
}

final _goalStatus = utf8.encode('"goal_status"');

/// The lines of [bytes] that have [marker] in them, in order.
Iterable<String> _linesWith(Uint8List bytes, List<int> marker) sync* {
  final first = marker.first;
  var at = 0;
  search:
  while (at <= bytes.length - marker.length) {
    if (bytes[at] != first) {
      at++;
      continue;
    }
    for (var i = 1; i < marker.length; i++) {
      if (bytes[at + i] != marker[i]) {
        at++;
        continue search;
      }
    }
    final start = bytes.lastIndexOf(0x0a, at) + 1;
    var end = bytes.indexOf(0x0a, at);
    if (end < 0) end = bytes.length;
    yield utf8.decode(
      Uint8List.sublistView(bytes, start, end),
      allowMalformed: true,
    );
    at = end + 1;
  }
}

Map<String, Object?>? _decode(String line) {
  try {
    return (jsonDecode(line) as Map).cast<String, Object?>();
  } on Object {
    return null;
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

List<ClaudeProjectSummary> _scan(String root, String cachePath) {
  final dir = Directory(root);
  if (!dir.existsSync()) return const [];
  final cache = _SummaryCache.load(cachePath, root);
  final byCwd = <String, List<ClaudeSessionSummary>>{};
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
        ClaudeProjectSummary(
          path: cwd,
          sessions: sessions
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
        ),
  ]..sort((a, b) => b.updatedAt!.compareTo(a.updatedAt!));
  return projects;
}

/// What [_Summary] made of each session file, kept between runs: reading
/// them all again is what made the first listing slow. A file is read again
/// only once its size or time of change differs, and then only what was
/// appended to it (a session at work grows by hundreds of MB, and is listed
/// again each time the app comes back to the front); only the files still
/// there are kept, so it stays a few hundred bytes a session. Anything amiss
/// with it (unreadable, another version, another folder) and it starts over.
class _SummaryCache {
  _SummaryCache._(this._path, this._root, this._old);

  /// Raise it whenever [_Summary] makes something else of a file.
  static const _version = 3;

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

  ClaudeSessionSummary? summarize(File file) {
    final stat = file.statSync();
    if (stat.type == FileSystemEntityType.notFound) return null;
    final size = stat.size;
    final modified = stat.modified.microsecondsSinceEpoch;
    final old = _old[file.path];
    final kept = old is Map ? _Summary.fromJson(old) : null;
    if (kept != null && kept.size == size && kept.modified == modified) {
      _fresh[file.path] = old;
      return kept.session(file.path);
    }
    // Stat before reading: a write meanwhile shows as a change next time.
    final read =
        (kept == null ? null : _Summary.readOn(file, kept)) ??
        _Summary.readOn(file, const _Summary()) ??
        const _Summary();
    final summary = read.at(size: size, modified: modified);
    _fresh[file.path] = summary.toJson();
    _changed = true;
    return summary.session(file.path);
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

/// What a session file says of itself (title, place and time), as far as
/// it was read: to [scanned], the end of its last whole line then. Claude
/// Code only appends to it, so what it says once grown is this and what
/// the lines after say; [mark], the bytes before [scanned], tells whether
/// it was only appended to. Raise [_SummaryCache._version] when changing
/// what it makes of a file.
class _Summary {
  const _Summary({
    this.cwd,
    this.prompt,
    this.named,
    this.generated,
    this.said,
    this.scanned = 0,
    this.mark = '',
    this.size,
    this.modified,
  });

  /// [json] as [toJson] wrote it; null when it is not.
  static _Summary? fromJson(Map<Object?, Object?> json) {
    if (json case {
      'size': final int size,
      'modified': final int modified,
      'scanned': final int scanned,
      'mark': final String mark,
      'cwd': final String? cwd,
      'prompt': final String? prompt,
      'named': final String? named,
      'generated': final String? generated,
      'said': final int? said,
    }) {
      return _Summary(
        cwd: cwd,
        prompt: prompt,
        named: named,
        generated: generated,
        said: said,
        scanned: scanned,
        mark: mark,
        size: size,
        modified: modified,
      );
    }
    return null;
  }

  /// The folder it ran in, as its first line of the user's says.
  final String? cwd;

  /// The first line of the first thing the user typed, cut to 120
  /// characters: its title until it has one.
  final String? prompt;

  /// The last title the user gave it (`/rename`), and the last Claude Code
  /// generated: as written, blank too (then it is not titled so).
  final String? named;
  final String? generated;

  /// When its last message was written, in microseconds since the epoch.
  final int? said;

  final int scanned;

  /// Base64.
  final String mark;

  /// The file's size and time of change as it was read (see [at]).
  final int? size;
  final int? modified;

  /// How much of what is before [scanned] tells it again.
  static const _markLength = 32;

  _Summary at({required int size, required int modified}) => _Summary(
    cwd: cwd,
    prompt: prompt,
    named: named,
    generated: generated,
    said: said,
    scanned: scanned,
    mark: mark,
    size: size,
    modified: modified,
  );

  Map<String, Object?> toJson() => {
    'size': size,
    'modified': modified,
    'scanned': scanned,
    'mark': mark,
    'cwd': cwd,
    'prompt': prompt,
    'named': named,
    'generated': generated,
    'said': said,
  };

  /// The session it is; null for one with no conversation (e.g. only a
  /// failed start).
  ClaudeSessionSummary? session(String path) {
    final cwd = this.cwd;
    final prompt = this.prompt;
    if (cwd == null || prompt == null) return null;
    String? titled(String? title) =>
        title == null || title.isEmpty ? null : title;
    final name = p.basename(path);
    return ClaudeSessionSummary(
      id: name.substring(0, name.length - '.jsonl'.length),
      // The user's before the one Claude Code generated.
      title: titled(named) ?? titled(generated) ?? prompt,
      // When it was last talked in: the file is written to besides
      // (titles, the last prompt), by the CLI resuming it too.
      updatedAt: DateTime.fromMicrosecondsSinceEpoch(said ?? modified ?? 0),
      cwd: cwd,
      path: path,
    );
  }

  /// What [file] says: [kept], what was made of it up to where it was read
  /// last ([_Summary()] for nothing), with what came after. Null when it
  /// was not only appended to since, or could not be read.
  static _Summary? readOn(File file, _Summary kept) {
    final mark = base64Decode(kept.mark);
    final from = kept.scanned - mark.length;
    if (from < 0) return null;
    final Uint8List bytes;
    try {
      final opened = file.openSync();
      try {
        final length = opened.lengthSync();
        if (length < kept.scanned) return null;
        opened.setPositionSync(from);
        bytes = opened.readSync(length - from);
      } finally {
        opened.closeSync();
      }
    } on FileSystemException {
      return null;
    }
    if (bytes.length < mark.length) return null;
    for (var i = 0; i < mark.length; i++) {
      if (bytes[i] != mark[i]) return null;
    }
    final added = Uint8List.sublistView(bytes, mark.length);
    final end = added.lastIndexOf(0x0a) + 1;
    final before = Uint8List.sublistView(
      bytes,
      math.max(0, mark.length + end - _markLength),
      mark.length + end,
    );
    // A line written halfway counts as far as it reads; it is read again,
    // whole, next time.
    final text = utf8.decode(added, allowMalformed: true);
    String? lastTitle(String type, String key) {
      final at = text.lastIndexOf('"type":"$type"');
      if (at < 0) return null;
      final start = text.lastIndexOf('\n', at) + 1;
      final end = text.indexOf('\n', at);
      final line = text.substring(start, end < 0 ? text.length : end);
      try {
        return ((jsonDecode(line) as Map)[key] as String?)?.trim() ?? '';
      } on Object {
        return '';
      }
    }

    final lines = const LineSplitter().convert(text);
    var cwd = kept.cwd;
    var prompt = kept.prompt;
    for (final line in lines) {
      if (prompt != null) break;
      if (!line.contains('"type":"user"')) continue;
      final Map<String, Object?> entry;
      try {
        entry = (jsonDecode(line) as Map).cast<String, Object?>();
      } on Object {
        continue;
      }
      cwd ??= entry['cwd'] as String?;
      if (entry['isSidechain'] == true || entry['isMeta'] == true) continue;
      if (_promptText(entry) case final typed?) {
        final first = typed.trim().split('\n').first;
        prompt = first.length > 120 ? '${first.substring(0, 120)}…' : first;
      }
    }
    return _Summary(
      cwd: cwd,
      prompt: prompt,
      named: lastTitle('custom-title', 'customTitle') ?? kept.named,
      generated: lastTitle('ai-title', 'aiTitle') ?? kept.generated,
      said: _lastMessageTime(lines)?.microsecondsSinceEpoch ?? kept.said,
      scanned: kept.scanned + end,
      mark: base64Encode(before),
    );
  }
}

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
/// none (a command's output, an interruption). A command typed with what
/// it is to do (`/goal …`) is that, as typed.
String? _promptText(Map<String, Object?> entry) {
  final message = entry['message'];
  if (message is! Map) return null;
  final content = message['content'];
  final blocks = content is List<Object?> ? content : const <Object?>[];
  final text = switch (content) {
    final String text => text,
    _ => [
      for (final block in blocks)
        if (block is Map && block['type'] == 'text')
          if (block['text'] as String? ?? '' case final text
              // Not the name the CLI gives an image ahead of it
              // (`[Image #1]`), nor a note for the model the app sends
              // ahead of what was typed (the file open in the editor, the
              // phone written from).
              when !_imageName.hasMatch(text) &&
                  !text.trimLeft().startsWith('<system-reminder>'))
            text,
    ].join('\n'),
  };
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    final images = blocks.any((b) => b is Map && b['type'] == 'image');
    return images ? '' : null;
  }
  if (trimmed.startsWith('<')) {
    final name = _commandName.firstMatch(trimmed)?[1]?.trim();
    final args = _commandArgs.firstMatch(trimmed)?[1]?.trim();
    if (name == null || args == null || args.isEmpty) return null;
    return '${name.startsWith('/') ? name : '/$name'} $args';
  }
  if (trimmed.startsWith('[Request interrupted')) return null;
  return trimmed;
}

/// A text block that is only an image's name, as the CLI puts ahead of it.
final _imageName = RegExp(r'^\s*\[Image #\d+\]\s*$');

/// A command the CLI ran, as it keeps it.
final _commandName = RegExp(r'<command-name>([\s\S]*?)</command-name>');
final _commandArgs = RegExp(r'<command-args>([\s\S]*?)</command-args>');

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
    if (_kept(entry) &&
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
      if (_kept(entry)) entry,
  ];
}

/// [turns] of [branch], ending before the line [before] (its end when
/// null), cut where the user began one: a turn's calls and their results
/// stay together. Past some [bytes], it is cut within a turn, where the
/// agent began a message with no call before it unanswered. The first
/// page has how the goal stood all along: it is worked out from every
/// record, which no other page has then.
ClaudeHistoryPage _page(
  _Branch branch, {
  required int turns,
  required int bytes,
  String? before,
}) {
  var end = branch.length;
  if (before != null) {
    // Gone, the session rewound meanwhile: nothing more before it.
    end = branch.indexOfId(before);
    if (end < 0) return const ClaudeHistoryPage([]);
  }
  var start = 0;
  var seen = 0;
  var size = 0;
  // Calls answered after the line at hand, made at or before it.
  final answered = <String>{};
  for (var i = end - 1; i >= 0; i--) {
    final entry = branch[i] = _slim(branch[i]);
    size += jsonEncode(entry).length;
    for (final block in _blocks(entry)) {
      switch (block) {
        case {'type': 'tool_result', 'tool_use_id': final String id}:
          answered.add(id);
        case {'type': 'tool_use', 'id': final String id}:
          answered.remove(id);
      }
    }
    final cut = _isPrompt(entry)
        ? ++seen >= turns || size >= bytes
        : size >= bytes && answered.isEmpty && _beginsMessage(branch, i);
    if (cut) {
      start = i;
      break;
    }
  }
  return ClaudeHistoryPage([
    if (before == null)
      for (var i = 0; i < start; i++)
        if (branch.isGoalAt(i)) branch[i],
    for (var i = start; i < end; i++)
      if (before == null || !branch.isGoalAt(i)) branch[i],
  ], earlier: start > 0 ? branch.idAt(start) : null);
}

/// A session file's lines as its pages are read (see
/// [ClaudeSessions.readPage]): where each is, and what of it places it in
/// the conversation. Kept between pages, and read on from [scanned] once
/// the file has grown, as [_Summary] is: every page of a long session read
/// the whole of it again (hundreds of MB, decoded line by line), to show a
/// few hundred KB of it.
class _Lines {
  _Lines();

  final starts = <int>[];
  final ends = <int>[];

  /// [_keptLine], [_sidechain], [_goal].
  final kinds = <int>[];
  final ids = <String?>[];

  /// `parentUuid`, else `logicalParentUuid` (across a compaction).
  final parents = <String?>[];

  /// To the end of the last line read whole; [mark], the bytes before it
  /// (see [_Summary.scanned]).
  var scanned = 0;
  var mark = Uint8List(0);

  static const _keptLine = 1;
  static const _sidechain = 2;
  static const _goal = 4;

  static final _json = utf8.decoder.fuse(json.decoder);

  /// The line at [start] to [end] of [bytes]; null when it does not read.
  static Map<String, Object?>? _decode(Uint8List bytes, int start, int end) {
    if (end <= start) return null;
    try {
      final entry = _json.convert(Uint8List.sublistView(bytes, start, end));
      return entry is Map ? entry.cast<String, Object?>() : null;
    } on Object {
      return null;
    }
  }

  /// [kept] (changed), with the lines [file] has after it; all its lines
  /// when null. Null when it was not only appended to since.
  static _Lines? readOn(RandomAccessFile file, _Lines? kept) {
    final mark = kept?.mark ?? Uint8List(0);
    final scanned = kept?.scanned ?? 0;
    final from = scanned - mark.length;
    final length = file.lengthSync();
    if (from < 0 || length < scanned) return null;
    file.setPositionSync(from);
    final bytes = file.readSync(length - from);
    if (bytes.length < mark.length) return null;
    for (var i = 0; i < mark.length; i++) {
      if (bytes[i] != mark[i]) return null;
    }
    final lines = kept ?? _Lines();
    var at = mark.length;
    var done = at;
    while (at < bytes.length) {
      var end = bytes.indexOf(0x0a, at);
      final whole = end >= 0;
      if (!whole) end = bytes.length;
      final entry = _decode(bytes, at, end);
      // Written halfway: read next time, whole.
      if (!whole && entry == null) break;
      if (entry != null) {
        final parent = entry['parentUuid'] ?? entry['logicalParentUuid'];
        lines.starts.add(from + at);
        lines.ends.add(from + end);
        lines.ids.add(entry['uuid'] is String ? entry['uuid'] as String : null);
        lines.parents.add(parent is String ? parent : null);
        lines.kinds.add(
          (_kept(entry) ? _keptLine : 0) |
              (entry['isSidechain'] == true ? _sidechain : 0) |
              (_kept(entry) && entry['type'] == 'attachment' ? _goal : 0),
        );
      }
      at = done = whole ? end + 1 : end;
    }
    lines
      ..scanned = from + done
      ..mark = Uint8List.fromList(
        Uint8List.sublistView(
          bytes,
          math.max(0, done - _Summary._markLength),
          done,
        ),
      );
    return lines;
  }

  /// The lines along the branch that ends with the last message, oldest
  /// first, as [_branch] has them.
  List<int> branch() {
    final byId = <String, int>{for (var i = 0; i < ids.length; i++) ?ids[i]: i};
    int? leaf;
    for (var i = kinds.length - 1; i >= 0; i--) {
      if (kinds[i] & (_keptLine | _sidechain) == _keptLine && ids[i] != null) {
        leaf = i;
        break;
      }
    }
    final rows = <int>[];
    final seen = <String>{};
    for (var row = leaf; row != null;) {
      if (!seen.add(ids[row]!)) break;
      rows.add(row);
      row = switch (parents[row]) {
        final parent? => byId[parent],
        null => null,
      };
    }
    return [
      for (final row in rows.reversed)
        if (kinds[row] & _keptLine != 0) row,
    ];
  }

  /// Line [row], read from [file].
  Map<String, Object?> entry(RandomAccessFile file, int row) {
    file.setPositionSync(starts[row]);
    final bytes = file.readSync(ends[row] - starts[row]);
    return _decode(bytes, 0, bytes.length) ?? const {};
  }
}

/// The conversation along the branch [_Lines.branch] gives, each line read
/// only once asked for: a page is a few hundred of thousands.
class _Branch extends ListBase<Map<String, Object?>> {
  _Branch(this._file, this._lines) : _rows = _lines.branch();

  final RandomAccessFile _file;
  final _Lines _lines;
  final List<int> _rows;
  final _read = <int, Map<String, Object?>>{};

  @override
  int get length => _rows.length;

  @override
  set length(int length) => throw UnsupportedError('A branch as it is');

  @override
  Map<String, Object?> operator [](int index) =>
      _read[index] ??= _lines.entry(_file, _rows[index]);

  @override
  void operator []=(int index, Map<String, Object?> entry) =>
      _read[index] = entry;

  String? idAt(int index) => _lines.ids[_rows[index]];

  /// Whether line [index] is how the goal stood (see [_kept]).
  bool isGoalAt(int index) => _lines.kinds[_rows[index]] & _Lines._goal != 0;

  int indexOfId(String id) {
    for (var i = 0; i < _rows.length; i++) {
      if (_lines.ids[_rows[i]] == id) return i;
    }
    return -1;
  }
}

/// Whether [entry] is the user beginning a turn.
bool _isPrompt(Map<String, Object?> entry) =>
    entry['type'] == 'user' &&
    entry['isSidechain'] != true &&
    entry['isMeta'] != true &&
    entry['isCompactSummary'] != true &&
    entry['uuid'] is String &&
    _promptText(entry) != null;

/// [entry] without what is not shown of it, which may be most of it: a
/// file read whole (kept twice, in the call's result for the model and in
/// the CLI's), the CLI's copy of the pictures a call gave the model (they
/// are shown from the call's result), a file as it was before an edit.
Map<String, Object?> _slim(Map<String, Object?> entry) {
  final result = entry['toolUseResult'];
  final read = result is Map && result['file'] is Map;
  final edit = result is Map && result.containsKey('originalFile');
  // An MCP tool's result, as the call's: its pictures twice.
  final pictures =
      result is List &&
      result.any((block) => block is Map && block['type'] == 'image');
  final message = entry['message'];
  final results =
      message is Map &&
      message['content'] is List &&
      _blocks(entry).any((block) => block['type'] == 'tool_result');
  if (!read && !edit && !pictures && !results) return entry;
  final slim = {...entry};
  if (read) {
    final file = {...result['file'] as Map}
      ..remove('content')
      ..remove('base64');
    slim['toolUseResult'] = {...result, 'file': file};
  } else if (edit) {
    slim['toolUseResult'] = {...result}..remove('originalFile');
  } else if (pictures) {
    slim['toolUseResult'] = [
      for (final block in result)
        if (block is! Map || block['type'] != 'image') block,
    ];
  }
  if (results) {
    // A file read is shown by its start (a failed call by its end: left
    // whole).
    Object? cut(Object? content, bool shorten) => switch (content) {
      final String text when shorten && text.length > _readShown =>
        '${text.substring(0, _readShown)}…',
      final List<Object?> blocks => [
        for (final block in blocks) cut(block, shorten),
      ],
      {'type': 'text', 'text': final String text} => {
        ...content as Map,
        'text': cut(text, shorten),
      },
      _ => content,
    };
    slim['message'] = {
      ...message,
      'content': [
        for (final block in _blocks(entry))
          if (block['type'] == 'tool_result')
            {
              ...block,
              'content': cut(
                block['content'],
                read && block['is_error'] != true,
              ),
            }
          else
            block,
      ],
    };
  }
  return slim;
}

/// How much of a file read is shown, at most.
const _readShown = 4000;

/// The content blocks of [entry]'s message.
Iterable<Map<Object?, Object?>> _blocks(Map<String, Object?> entry) =>
    switch (entry['message']) {
      {'content': final List<Object?> content} =>
        content.whereType<Map<Object?, Object?>>(),
      _ => const [],
    };

/// Whether line [index] of [branch] is the first of a message of the
/// agent's: the lines before it have a message whole (the CLI keeps one a
/// line per block).
bool _beginsMessage(List<Map<String, Object?>> branch, int index) {
  final entry = branch[index];
  if (entry['type'] != 'assistant' ||
      entry['isSidechain'] == true ||
      entry['uuid'] is! String) {
    return false;
  }
  String? messageId(Map<String, Object?> entry) => switch (entry['message']) {
    {'id': final String id} => id,
    _ => null,
  };
  final id = messageId(entry);
  for (var i = index - 1; i >= 0; i--) {
    if (branch[i]['type'] == 'assistant') {
      return id == null || messageId(branch[i]) != id;
    }
  }
  return true;
}

/// Whether [entry] is read back: a message, or how the session's goal
/// stood (set, checked, met), which may follow the last message.
bool _kept(Map<String, Object?> entry) => switch (entry['type']) {
  'user' || 'assistant' || 'system' => true,
  'attachment' => switch (entry['attachment']) {
    {'type': 'goal_status'} => true,
    _ => false,
  },
  _ => false,
};
