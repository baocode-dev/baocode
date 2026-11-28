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
import 'session_index.dart';

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
  ///
  /// One listing at a time: asked again meanwhile (each remote project of a
  /// host asks as the app starts), it is listed once more after, for all
  /// who asked. A listing each had every long session read as many times
  /// at once, and took a server's memory whole.
  Future<List<ClaudeProjectSummary>> projects() async {
    final root = '${await _config()}/projects';
    final cache = cacheFile;
    final key = '$cache\n$root';
    Future<List<ClaudeProjectSummary>> scan() =>
        _scanning[key] = Isolate.run(() => _scan(root, cache)).whenComplete(() {
          // Not returned: it is this very future, which would be waited for.
          _scanning.remove(key);
        });
    final running = _scanning[key];
    if (running == null) return scan();
    return _scanNext[key] ??= running.then<void>((_) {}, onError: (_) {}).then((
      _,
    ) {
      _scanNext.remove(key);
      return scan();
    });
  }

  static final _scanning = <String, Future<List<ClaudeProjectSummary>>>{};
  static final _scanNext = <String, Future<List<ClaudeProjectSummary>>>{};

  /// The session's conversation along the branch it ended on.
  static Future<List<Map<String, Object?>>> read(String path) =>
      Isolate.run(() => _branch(path));

  /// The last [turns] of the session's conversation, along the branch it
  /// ended on; or the [turns] before the line [before] (see
  /// [ClaudeHistoryPage.earlier]). A long one is shown sooner so, from a
  /// remote project's host above all.
  ///
  /// Whole-turn aligned: once at least one complete turn is in the page,
  /// exceeding [bytes] stops cleanly at the already-completed turn boundary
  /// rather than splitting an earlier turn in half. A single turn alone is
  /// kept whole up to [maxSingleTurnBytes] so it arrives already folded
  /// instead of unfolding and later collapsing on scroll-up.
  ///
  /// When [until] is given, extends the page back at least to the turn
  /// starting at (or containing) [until] in one read (for ⌘F jump-to-match).
  static Future<ClaudeHistoryPage> readPage(
    String path, {
    required int turns,
    String? before,
    String? until,
    int bytes = pageBytes,
    int maxSingleTurnBytes = maxTurnBytes,
    String? indexDir,
  }) async {
    final kept = _indexKept[path];
    final dir = indexDir ?? indexCacheDir;
    final (index, page) = await Isolate.run(() {
      final store = SessionIndexStore(cacheDir: dir);
      final index = store.openSync(path, inMemory: kept);
      final file = File(path).openSync();
      try {
        final branch = _Branch(file, index);
        return (
          index,
          _page(
            branch,
            turns: turns,
            before: before,
            until: until,
            bytes: bytes,
            maxSingleTurnBytes: maxSingleTurnBytes,
          ),
        );
      } finally {
        file.closeSync();
      }
    });
    _rememberIndex(path, index);
    return page;
  }

  /// Searches turns on the active branch strictly before [before] (or all
  /// turns when [before] is null) using the session's persisted
  /// [SessionIndex], without re-reading `.jsonl` when unchanged.
  static Future<List<IndexedTurnHit>> searchEarlier(
    String path,
    String patternSource, {
    required bool caseSensitive,
    String? before,
    String? indexDir,
  }) async {
    final kept = _indexKept[path];
    final dir = indexDir ?? indexCacheDir;
    final (index, hits) = await Isolate.run(() {
      final store = SessionIndexStore(cacheDir: dir);
      final index = store.openSync(path, inMemory: kept);
      final pattern = RegExp(patternSource, caseSensitive: caseSensitive);
      return (index, index.searchTurns(pattern, beforeId: before));
    });
    _rememberIndex(path, index);
    return hits;
  }

  static void _rememberIndex(String path, SessionIndex index) {
    _indexKept
      ..remove(path)
      ..[path] = index;
    if (_indexKept.length > 16) _indexKept.remove(_indexKept.keys.first);
  }

  /// Optional directory for persisted per-session `.idx.gz` sidecar files.
  static String? indexCacheDir;

  /// The indexes of the sessions whose pages were read or searched last.
  static final _indexKept = <String, SessionIndex>{};

  /// How much a page of [readPage] comes to, about.
  static const pageBytes = 512 * 1024;

  /// Safety cap for a single slimmed turn before forcing a mid-turn cut.
  static const maxTurnBytes = 4 * 1024 * 1024;

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
  final byId = <String, int>{
    for (var i = 0; i < entries.length; i++)
      if (entries[i]['uuid'] case final String uuid) uuid: i,
  };
  String? parentOf(Map<String, Object?> entry) =>
      (entry['parentUuid'] ?? entry['logicalParentUuid']) as String?;
  final seen = <String>{};
  int? previousKept(int before) {
    for (var i = before - 1; i >= 0; i--) {
      final entry = entries[i];
      if (_kept(entry) && entry['isSidechain'] != true) {
        final uuid = entry['uuid'];
        if (uuid is String && !seen.contains(uuid)) return i;
      }
    }
    return null;
  }

  final int? leaf;
  if (before != null) {
    final cut = byId[before];
    if (cut == null) throw StateError('No message $before in session $id');
    leaf = switch (parentOf(entries[cut])) {
      final parent? => byId[parent] ?? previousKept(cut),
      null => null,
    };
  } else {
    leaf = previousKept(entries.length);
  }
  // The chain to it, every line of it as written (attachments, compaction
  // boundaries): what the CLI makes of the original, it makes of this.
  final chain = <Map<String, Object?>>[];
  for (var row = leaf; row != null;) {
    final entry = entries[row];
    if (!seen.add(entry['uuid'] as String)) break;
    chain.add(entry);
    row = switch (parentOf(entry)) {
      // The CLI sometimes writes a dangling `logicalParentUuid` (or
      // `parentUuid`) whose target is missing from the file, e.g. at a
      // compaction boundary: fall back to the nearest earlier kept line.
      final parent? => byId[parent] ?? previousKept(row),
      null => null,
    };
  }
  if (chain.isEmpty) throw StateError('Nothing to fork in session $id');
  // Tools called at once are a reply of a line each, and their results
  // hang off those lines, not one after another: the chain passes by all
  // but one. The CLI takes them back as it resumes; so must the copy, else
  // its history is not the original's (nor is its prompt cache).
  final replies = {
    for (final entry in chain)
      if (entry['type'] == 'assistant') ?_messageId(entry),
  };
  final calls = <String>{};
  final copied = <Map<String, Object?>>[];
  for (final entry in entries) {
    final uuid = entry['uuid'];
    if (uuid is! String || entry['isSidechain'] == true) continue;
    final keep =
        seen.contains(uuid) ||
        (entry['type'] == 'assistant' && replies.contains(_messageId(entry))) ||
        (entry['type'] == 'user' && _toolResults(entry).any(calls.contains));
    if (!keep) continue;
    copied.add(entry);
    calls.addAll(_toolUses(entry));
  }
  final out = StringBuffer();
  for (final entry in copied) {
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

/// The id of the model's reply [entry] is (a line of).
String? _messageId(Map<String, Object?> entry) => switch (entry['message']) {
  {'id': final String id} => id,
  _ => null,
};

/// The ids of the tools [entry] calls.
Iterable<String> _toolUses(Map<String, Object?> entry) => [
  for (final block in _blocks(entry))
    if (block case {'type': 'tool_use', 'id': final String id}) id,
];

/// The ids of the tool calls [entry] answers.
Iterable<String> _toolResults(Map<String, Object?> entry) => [
  for (final block in _blocks(entry))
    if (block case {'type': 'tool_result', 'tool_use_id': final String id}) id,
];

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
  static const _version = 6;

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
    // A first listing of many long sessions takes minutes: what was read is
    // kept as it goes, lest a run cut short (the server killed) leave
    // nothing, and the next read it all again.
    if (_sinceWritten.elapsed > const Duration(seconds: 5)) {
      _write({..._old, ..._fresh});
    }
    return summary.session(file.path);
  }

  final _sinceWritten = Stopwatch()..start();

  /// Writes it, if anything changed: whole, so a run cut short leaves the
  /// old one rather than half of a new one.
  void save() {
    if (!_changed && _fresh.length == _old.length) return;
    _write(_fresh);
  }

  void _write(Map<String, Object?> files) {
    _sinceWritten.reset();
    // Its own: two listings may save at once.
    final temp = File('$_path.$pid.${DateTime.now().microsecondsSinceEpoch}');
    try {
      temp.parent.createSync(recursive: true);
      temp.writeAsStringSync(
        jsonEncode({'version': _version, 'root': _root, 'files': files}),
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
    this.command,
    this.replied = false,
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
      'command': final String? command,
      'replied': final bool replied,
      'named': final String? named,
      'generated': final String? generated,
      'said': final int? said,
    }) {
      return _Summary(
        cwd: cwd,
        prompt: prompt,
        command: command,
        replied: replied,
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

  /// The first argument-less slash command the user ran (e.g. `/review`):
  /// used as a fallback title when the assistant actually replied and no
  /// prompt or title was recorded.
  final String? command;

  /// Whether a non-synthetic assistant message appeared in the file.
  final bool replied;

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
    command: command,
    replied: replied,
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
    'command': command,
    'replied': replied,
    'named': named,
    'generated': generated,
    'said': said,
  };

  /// The session it is; null for one with no conversation (e.g. only a
  /// failed start or an isolated local command).
  ClaudeSessionSummary? session(String path) {
    final cwd = this.cwd;
    if (cwd == null) return null;
    String? titled(String? title) =>
        title == null || title.isEmpty ? null : title;
    final title =
        titled(named) ??
        titled(generated) ??
        prompt ??
        (replied ? command : null);
    if (title == null) return null;
    final name = p.basename(path);
    return ClaudeSessionSummary(
      id: name.substring(0, name.length - '.jsonl'.length),
      // The user's before the one Claude Code generated.
      title: title,
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
    final RandomAccessFile opened;
    try {
      opened = file.openSync();
    } on FileSystemException {
      return null;
    }
    try {
      return _readOn(opened, kept);
    } on FileSystemException {
      return null;
    } finally {
      opened.closeSync();
    }
  }

  /// How much of a file is read at once: a session may be GBs, a server's
  /// memory not.
  static const _chunk = 4 << 20;

  static _Summary? _readOn(RandomAccessFile file, _Summary kept) {
    final mark = base64Decode(kept.mark);
    final from = kept.scanned - mark.length;
    if (from < 0) return null;
    final length = file.lengthSync();
    if (length < kept.scanned) return null;
    file.setPositionSync(from);
    final head = file.readSync(mark.length);
    if (head.length < mark.length) return null;
    for (var i = 0; i < mark.length; i++) {
      if (head[i] != mark[i]) return null;
    }
    var cwd = kept.cwd;
    var prompt = kept.prompt;
    var command = kept.command;
    var replied = kept.replied;
    // Where the lines that may tell the rest are, read once all are seen:
    // only the last that does counts.
    (int, int)? named;
    (int, int)? generated;
    final said = ListQueue<(int, int)>();
    void line(Uint8List bytes, int start, int end) {
      if (prompt == null && _has(bytes, _userType)) {
        if (SessionIndex.decodeBytes(bytes) case final entry?) {
          cwd ??= entry['cwd'] as String?;
          if (entry['isSidechain'] != true && entry['isMeta'] != true) {
            if (_promptText(entry) case final typed?) {
              final first = typed.trim().split('\n').first;
              prompt = first.length > 120
                  ? '${first.substring(0, 120)}…'
                  : first;
            } else {
              command ??= _commandOnly(entry);
            }
          }
        }
      }
      if (!replied &&
          _has(bytes, _assistantType) &&
          !_has(bytes, _syntheticModel)) {
        replied = true;
      }
      if (_has(bytes, _customTitleType)) named = (start, end);
      if (_has(bytes, _aiTitleType)) generated = (start, end);
      if (_has(bytes, _timestamp) &&
          (_has(bytes, _userType) || _has(bytes, _assistantType))) {
        said.add((start, end));
        // Each one reads, but for a line cut short.
        if (said.length > 16) said.removeFirst();
      }
    }

    // Where the bytes in [carry] begin: the line not yet ended there.
    var at = kept.scanned;
    var carry = Uint8List(0);
    for (var read = kept.scanned; read < length;) {
      final chunk = file.readSync(math.min(_chunk, length - read));
      if (chunk.isEmpty) break;
      read += chunk.length;
      final bytes = carry.isEmpty
          ? chunk
          : (BytesBuilder(copy: false)
                  ..add(carry)
                  ..add(chunk))
                .takeBytes();
      var start = 0;
      for (
        var end = bytes.indexOf(0x0a, carry.length);
        end >= 0;
        end = bytes.indexOf(0x0a, start)
      ) {
        line(Uint8List.sublistView(bytes, start, end), at + start, at + end);
        start = end + 1;
      }
      carry = Uint8List.sublistView(bytes, start);
      at += start;
    }
    // A line written halfway counts as far as it reads; it is read again,
    // whole, next time.
    if (carry.isNotEmpty) line(carry, at, at + carry.length);
    final scanned = at;

    Map<String, Object?>? entryAt((int, int) where) {
      final (start, end) = where;
      file.setPositionSync(start);
      final bytes = file.readSync(end - start);
      return SessionIndex.decodeBytes(bytes);
    }

    String? title((int, int)? where, String key) {
      if (where == null) return null;
      return switch (entryAt(where)?[key]) {
        final String title => title.trim(),
        _ => '',
      };
    }

    int? lastSaid() {
      for (final where in said.toList().reversed) {
        final entry = entryAt(where);
        if (entry == null) continue;
        if (entry['type'] != 'user' && entry['type'] != 'assistant') continue;
        if (entry['timestamp'] case final String time) {
          if (DateTime.tryParse(time) case final parsed?) {
            return parsed.toLocal().microsecondsSinceEpoch;
          }
        }
      }
      return null;
    }

    final markFrom = math.max(from, scanned - _markLength);
    file.setPositionSync(markFrom);
    final before = file.readSync(scanned - markFrom);
    return _Summary(
      cwd: cwd,
      prompt: prompt,
      command: command,
      replied: replied,
      named: title(named, 'customTitle') ?? kept.named,
      generated: title(generated, 'aiTitle') ?? kept.generated,
      said: lastSaid() ?? kept.said,
      scanned: scanned,
      mark: base64Encode(before),
    );
  }

  static final _userType = utf8.encode('"type":"user"');
  static final _assistantType = utf8.encode('"type":"assistant"');
  static final _syntheticModel = utf8.encode('"<synthetic>"');
  static final _customTitleType = utf8.encode('"type":"custom-title"');
  static final _aiTitleType = utf8.encode('"type":"ai-title"');
  static final _timestamp = utf8.encode('"timestamp"');
}

/// Whether [marker] is in [bytes].
bool _has(Uint8List bytes, List<int> marker) {
  final first = marker.first;
  final last = bytes.length - marker.length;
  search:
  for (var at = bytes.indexOf(first); at >= 0 && at <= last;) {
    for (var i = 1; i < marker.length; i++) {
      if (bytes[at + i] != marker[i]) {
        at = bytes.indexOf(first, at + 1);
        continue search;
      }
    }
    return true;
  }
  return false;
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
    // The app's note alone, nothing typed, as the bots' world is sent when
    // the user said nothing: a turn of its own, as the bots' notes are.
    final noted = blocks.any(
      (b) =>
          b is Map &&
          b['type'] == 'text' &&
          (b['text'] as String? ?? '').trimLeft().startsWith(
            '<system-reminder>',
          ),
    );
    return images || noted ? '' : null;
  }
  // The app's note to one of its bots (what happened in a group, say):
  // a turn of its own, as what was typed is. A bot's conversation may have
  // nothing else: not listed, it would be started anew each run.
  if (_botEvent.firstMatch(trimmed) case final event?) {
    return event[1]!.trim();
  }
  // A message handed from another conversation or subagent
  // (`SessionTools.agentMessage`): a conversation started by another agent
  // may have nothing else, so unwrap its body as the prompt.
  if (_unwrapAgentMessage(trimmed) case final body?) {
    return body;
  }
  if (_isCommandWrapper(trimmed)) {
    final name = _commandName.firstMatch(trimmed)?[1]?.trim();
    final args = _commandArgs.firstMatch(trimmed)?[1]?.trim();
    if (name == null || args == null || args.isEmpty) return null;
    return '${name.startsWith('/') ? name : '/$name'} $args';
  }
  if (_isCliNote(trimmed)) return null;
  if (trimmed.startsWith('[Request interrupted')) return null;
  return trimmed;
}

/// The command name of an argument-less slash command (e.g. `/review`), or
/// null when [entry] is not one.
String? _commandOnly(Map<String, Object?> entry) {
  final message = entry['message'];
  if (message is! Map) return null;
  final content = message['content'];
  final text = switch (content) {
    final String text => text,
    final List<Object?> blocks => [
      for (final block in blocks)
        if (block is Map && block['type'] == 'text')
          block['text'] as String? ?? '',
    ].join('\n'),
    _ => '',
  };
  final trimmed = text.trim();
  if (!_isCommandWrapper(trimmed)) return null;
  final name = _commandName.firstMatch(trimmed)?[1]?.trim();
  if (name == null || name.isEmpty) return null;
  return name.startsWith('/') ? name : '/$name';
}

String? _unwrapAgentMessage(String trimmed) {
  if (!trimmed.startsWith('<agent-message')) return null;
  if (_agentMessage.firstMatch(trimmed) case final match?) {
    final body = match[1]!.trim();
    final tail = match[2]?.trim() ?? '';
    if (tail.isEmpty) return body;
    return body.isEmpty ? tail : '$body\n$tail';
  }
  if (_agentMessageOpen.firstMatch(trimmed) case final match?) {
    return match[1]!.trim();
  }
  return null;
}

bool _isCommandWrapper(String trimmed) =>
    trimmed.startsWith('<command-name>') ||
    trimmed.startsWith('<command-message>') ||
    trimmed.startsWith('<command-args>');

bool _isCliNote(String trimmed) =>
    trimmed.startsWith('<local-command-') ||
    trimmed.startsWith('<system-reminder>') ||
    trimmed.startsWith('<task-notification>') ||
    trimmed.startsWith('<bash-input>') ||
    trimmed.startsWith('<bash-stdout>') ||
    trimmed.startsWith('<bash-stderr>') ||
    trimmed.startsWith('<ide_opened_file>') ||
    trimmed.startsWith('<ide_selection>');

/// A text block that is only an image's name, as the CLI puts ahead of it.
final _imageName = RegExp(r'^\s*\[Image #\d+\]\s*$');

/// A note of the app's to a bot (`bot_prompt.dart`'s `botEventMessage`).
final _botEvent = RegExp(r'^<bao-event>([\s\S]*?)(?:</bao-event>|$)');

/// A message handed from another conversation or subagent.
final _agentMessage = RegExp(
  r'^<agent-message\b[^>]*>([\s\S]*)</agent-message>(?:\s*([\s\S]*))?$',
);
final _agentMessageOpen = RegExp(r'^<agent-message\b[^>]*>([\s\S]*)$');

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
  final byId = <String, int>{
    for (var i = 0; i < entries.length; i++)
      if (entries[i]['uuid'] case final String id) id: i,
  };
  final branch = <Map<String, Object?>>[];
  final seen = <String>{};
  int? previousKept(int before) {
    for (var i = before - 1; i >= 0; i--) {
      final entry = entries[i];
      if (_kept(entry) && entry['isSidechain'] != true) {
        final id = entry['uuid'];
        if (id is String && !seen.contains(id)) return i;
      }
    }
    return null;
  }

  for (var row = previousKept(entries.length); row != null;) {
    final entry = entries[row];
    final id = entry['uuid'] as String;
    if (!seen.add(id)) break;
    branch.add(entry);
    final parent =
        (entry['parentUuid'] ?? entry['logicalParentUuid']) as String?;
    row = parent == null ? null : (byId[parent] ?? previousKept(row));
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
  int maxSingleTurnBytes = ClaudeSessions.maxTurnBytes,
  String? before,
  String? until,
}) {
  var end = branch.length;
  if (before != null) {
    // Gone, the session rewound meanwhile: nothing more before it.
    end = branch.indexOfId(before);
    if (end < 0) return const ClaudeHistoryPage([]);
  }
  var untilIndex = -1;
  if (until != null) {
    final at = branch.indexOfId(until);
    if (at >= 0 && at < end) untilIndex = at;
  }
  var start = 0;
  var seen = 0;
  var size = 0;
  int? lastTurnBoundary;
  // Calls answered after the line at hand, made at or before it.
  final answered = <String>{};
  for (var i = end - 1; i >= 0; i--) {
    if (untilIndex < 0 && seen > 0 && size >= bytes) {
      start = lastTurnBoundary!;
      break;
    }
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
    if (branch.isPromptAt(i)) {
      seen++;
      lastTurnBoundary = i;
      if (untilIndex >= 0) {
        if (i <= untilIndex) {
          start = i;
          break;
        }
      } else if (seen >= turns || size >= bytes) {
        start = i;
        break;
      }
    } else if (untilIndex < 0 &&
        seen == 0 &&
        size >= maxSingleTurnBytes &&
        answered.isEmpty &&
        _beginsMessage(branch, i)) {
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

/// The conversation along the branch [SessionIndex.branch] gives, each line
/// read only once asked for: a page is a few hundred of thousands.
class _Branch extends ListBase<Map<String, Object?>> {
  _Branch(this._file, this._index) : _rows = _index.branch();

  final RandomAccessFile _file;
  final SessionIndex _index;
  final List<int> _rows;
  final _read = <int, Map<String, Object?>>{};

  @override
  int get length => _rows.length;

  @override
  set length(int length) => throw UnsupportedError('A branch as it is');

  @override
  Map<String, Object?> operator [](int index) =>
      _read[index] ??= _index.entry(_file, _rows[index]);

  @override
  void operator []=(int index, Map<String, Object?> entry) =>
      _read[index] = entry;

  String? idAt(int index) => _index.ids[_rows[index]];

  /// Whether line [index] is how the goal stood (see [_kept]).
  bool isGoalAt(int index) =>
      _index.kinds[_rows[index]] & SessionIndex.flagGoal != 0;

  /// Whether line [index] begins a user turn.
  bool isPromptAt(int index) =>
      _index.kinds[_rows[index]] & SessionIndex.flagPrompt != 0;

  int indexOfId(String id) {
    for (var i = 0; i < _rows.length; i++) {
      if (_index.ids[_rows[i]] == id) return i;
    }
    return -1;
  }
}

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
