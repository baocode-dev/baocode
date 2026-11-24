import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_agent/bao_agent.dart' show AgentPaths;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'claude_environment.dart';
import 'forked_runs.dart';

ForkedRuns? forkedRunsHere() => ForkedRunFiles();

/// [ForkedRuns] in Claude Code's own files: the session's `subagents/`
/// folder beside its transcript, looked at every [interval].
class ForkedRunFiles implements ForkedRuns {
  ForkedRunFiles({
    this.interval = const Duration(milliseconds: 700),
    @visibleForTesting this.folderOf,
  });

  final Duration interval;

  /// Where session [sessionId]'s subagents write; by default as the CLI
  /// does, in its config folder.
  final Future<String> Function(
    String cwd,
    String sessionId,
    Map<String, String>? env,
  )?
  folderOf;

  static Future<String> _folder(
    String cwd,
    String sessionId,
    Map<String, String>? env,
  ) async {
    final paths = AgentPaths.from({...await ClaudeEnvironment.of(), ...?env});
    final transcript =
        paths.findSession(sessionId) ?? paths.sessionFile(cwd, sessionId);
    return p.join(p.withoutExtension(transcript), 'subagents');
  }

  @override
  ForkedRun watch({
    required String cwd,
    required String sessionId,
    Map<String, String>? env,
    required void Function(Map<String, Object?> line) onLine,
  }) => _Tail(
    (folderOf ?? _folder)(cwd, sessionId, env),
    interval: interval,
    onLine: onLine,
  )..start();
}

class _Tail implements ForkedRun {
  _Tail(this._folder, {required this.interval, required this.onLine});

  final Future<String> _folder;
  final Duration interval;
  final void Function(Map<String, Object?> line) onLine;

  /// When it started: a subagent of this run is one made since.
  final DateTime _since = DateTime.now().subtract(const Duration(seconds: 2));

  Timer? _timer;
  bool _done = false;
  bool _reading = false;

  /// The run's own transcript, once found.
  File? _file;
  int _offset = 0;
  final List<int> _partial = [];

  void start() {
    _timer = Timer.periodic(interval, (_) => unawaited(_read()));
    unawaited(_read());
  }

  @override
  void finish() {
    _timer?.cancel();
    _timer = null;
    unawaited(_read(last: true));
  }

  @override
  void cancel() {
    _done = true;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _read({bool last = false}) async {
    if (_done || _reading) {
      // The last read, after the one under way.
      if (last && !_done) {
        unawaited(Future<void>.delayed(interval, () => _read(last: true)));
      }
      return;
    }
    _reading = true;
    try {
      final file = _file ??= await _find();
      if (file != null) await _readNew(file);
    } on Object catch (error) {
      debugPrint('Forked run not read: $error');
    } finally {
      _reading = false;
      if (last) _done = true;
    }
  }

  /// The run's subagent: made since it started, by no call (a slash
  /// command's) and by no other subagent (those it starts itself).
  Future<File?> _find() async {
    final folder = Directory(await _folder);
    if (!folder.existsSync()) return null;
    final found = <(DateTime, File)>[];
    await for (final entry in folder.list()) {
      if (entry is! File || !entry.path.endsWith('.meta.json')) continue;
      final made = entry.statSync().modified;
      if (made.isBefore(_since)) continue;
      final Object? meta;
      try {
        meta = jsonDecode(await entry.readAsString());
      } on FormatException {
        continue; // Being written.
      }
      if (meta is! Map ||
          meta['toolUseId'] != null ||
          meta['parentAgentId'] != null) {
        continue;
      }
      final transcript = File(
        '${entry.path.substring(0, entry.path.length - '.meta.json'.length)}'
        '.jsonl',
      );
      if (transcript.existsSync()) found.add((made, transcript));
    }
    if (found.isEmpty) return null;
    found.sort((a, b) => a.$1.compareTo(b.$1));
    return found.first.$2;
  }

  Future<void> _readNew(File file) async {
    final length = await file.length();
    if (length <= _offset) return;
    final open = await file.open();
    try {
      await open.setPosition(_offset);
      final bytes = await open.read(length - _offset);
      _offset += bytes.length;
      _partial.addAll(bytes);
    } finally {
      await open.close();
    }
    // Whole lines only: the last may be still being written.
    final end = _partial.lastIndexOf(10);
    if (end < 0) return;
    final text = utf8.decode(_partial.sublist(0, end), allowMalformed: true);
    _partial.removeRange(0, end + 1);
    for (final line in const LineSplitter().convert(text)) {
      if (line.trim().isEmpty || _done) continue;
      try {
        if (jsonDecode(line) case final Map<String, Object?> message) {
          onLine(message);
        }
      } on FormatException {
        // Not a line of its.
      }
    }
  }
}
