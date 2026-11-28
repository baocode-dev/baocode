import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'swarm_model.dart';

/// Reads the current [SwarmSnapshot] for [swarmId] under [brainDir], or null
/// when no swarm exists for that conversation yet.
///
/// When [activeSince] is given, worker transcripts last modified before
/// [activeSince] are treated as stale (from a prior process) so orphaned
/// workers do not appear stuck as `working`.
SwarmSnapshot? readSwarmSnapshotSync(
  String brainDir,
  String swarmId, {
  DateTime? activeSince,
  Map<String, DateTime> stoppedUntil = const {},
}) {
  final dir = Directory(
    p.join(brainDir, swarmId, '.system_generated', 'swarm'),
  );
  if (!dir.existsSync()) return null;
  final membersFile = File(p.join(dir.path, 'members.json'));
  if (!membersFile.existsSync()) return null;
  final boardFile = File(p.join(dir.path, 'board.jsonl'));
  final planFile = File(p.join(dir.path, 'plan.json'));
  final viewFile = File(p.join(dir.path, 'view.json'));
  try {
    final membersJson = membersFile.readAsStringSync();
    final membersMtime = membersFile.lastModifiedSync();
    final allowUnwrittenWorking =
        activeSince == null || !membersMtime.isBefore(activeSince);
    final boardJsonl = boardFile.existsSync()
        ? boardFile.readAsStringSync()
        : '';
    final planJson = planFile.existsSync() ? planFile.readAsStringSync() : null;
    final viewJson = viewFile.existsSync() ? viewFile.readAsStringSync() : null;

    final transcripts = <String, MemberTranscriptSummary>{};
    final stoppedMembers = <String>{};
    if (jsonDecode(membersJson) case {'members': final Map roster}) {
      for (final MapEntry(key: memberKey, value: entry) in roster.entries) {
        if (entry is! Map) continue;
        final name = '$memberKey';
        final convId = entry['conversation_id'];
        if (convId is! String || convId.isEmpty) continue;
        final tFile = File(
          p.join(
            brainDir,
            convId,
            '.system_generated',
            'logs',
            'transcript.jsonl',
          ),
        );
        final stopCutoff = stoppedUntil[name];
        if (!tFile.existsSync()) {
          if (stopCutoff != null) stoppedMembers.add(name);
          continue;
        }
        try {
          final mtime = tFile.lastModifiedSync();
          if (stopCutoff != null && !mtime.isAfter(stopCutoff)) {
            stoppedMembers.add(name);
          }
          final stale = activeSince != null && mtime.isBefore(activeSince);
          transcripts[convId] = summarizeWorkerTranscript(
            tFile.readAsStringSync(),
            stale: stale,
          );
        } on FileSystemException {
          // Being written; retry next poll.
        }
      }
    }
    return buildSwarmSnapshot(
      swarmId: swarmId,
      brainDir: brainDir,
      membersJson: membersJson,
      boardJsonl: boardJsonl,
      planJson: planJson,
      viewJson: viewJson,
      transcripts: transcripts,
      stoppedMembers: stoppedMembers,
      allowUnwrittenWorking: allowUnwrittenWorking,
    );
  } on Object {
    return null;
  }
}

/// Reads a worker's compact transcript steps from disk for the Members detail
/// inspector.
Future<List<SwarmWorkerStep>> readSwarmWorkerTranscript(
  String brainDir,
  String conversationId,
) async {
  if (brainDir.isEmpty || conversationId.isEmpty) return const [];
  final file = File(
    p.join(
      brainDir,
      conversationId,
      '.system_generated',
      'logs',
      'transcript.jsonl',
    ),
  );
  if (!file.existsSync()) return const [];
  try {
    return parseWorkerTranscriptSteps(await file.readAsString());
  } on Object {
    return const [];
  }
}

class _FileStamp {
  const _FileStamp(this.modifiedMicros, this.size);

  final int modifiedMicros;
  final int size;

  @override
  bool operator ==(Object other) =>
      other is _FileStamp &&
      other.modifiedMicros == modifiedMicros &&
      other.size == size;

  @override
  int get hashCode => Object.hash(modifiedMicros, size);
}

_FileStamp? _stampOf(FileStat stat) =>
    stat.type == FileSystemEntityType.notFound
    ? null
    : _FileStamp(stat.modified.microsecondsSinceEpoch, stat.size);

/// Incrementally reads an append-only UTF-8 JSONL file by byte offset.
///
/// Only complete newline-terminated lines advance [_offset]; any unterminated
/// trailing bytes are exposed as [trailingLine] without advancing [_offset], so
/// both half-written lines and final lines without a trailing `\n` are handled
/// safely without re-reading earlier bytes.
class _IncrementalJsonlReader {
  _FileStamp? _stamp;
  int _offset = 0;
  String? _trailingLine;
  DateTime? _lastMtime;

  String? get trailingLine => _trailingLine;
  DateTime? get lastMtime => _lastMtime;
  bool get exists => _stamp != null;

  void reset() {
    _stamp = null;
    _offset = 0;
    _trailingLine = null;
    _lastMtime = null;
  }

  /// Checks [file] via `statSync()` and reads only newly appended bytes when
  /// the file changed. Returns `true` if file presence or content changed.
  bool sync(
    File file, {
    required void Function() onReset,
    required void Function(String chunk) onCommittedChunk,
  }) {
    final stat = file.statSync();
    final nextStamp = _stampOf(stat);
    if (nextStamp == null) {
      final hadFile = _stamp != null || _offset != 0 || _trailingLine != null;
      if (hadFile) {
        reset();
        onReset();
      }
      return hadFile;
    }
    if (nextStamp == _stamp) {
      _lastMtime = stat.modified;
      return false;
    }

    // Truncated or overwritten in place with identical byte length.
    if (stat.size < _offset ||
        (stat.size == _offset && _trailingLine == null)) {
      _offset = 0;
      _trailingLine = null;
      onReset();
    }

    if (stat.size > _offset) {
      final raf = file.openSync(mode: FileMode.read);
      try {
        raf.setPositionSync(_offset);
        final bytes = raf.readSync(stat.size - _offset);
        var lastNl = -1;
        for (var i = bytes.length - 1; i >= 0; i--) {
          if (bytes[i] == 0x0A) {
            lastNl = i;
            break;
          }
        }
        if (lastNl >= 0) {
          final committed = utf8.decode(
            bytes.sublist(0, lastNl + 1),
            allowMalformed: true,
          );
          _offset += lastNl + 1;
          onCommittedChunk(committed);
        }
        final tailStart = lastNl + 1;
        if (tailStart < bytes.length) {
          try {
            _trailingLine = utf8.decode(bytes.sublist(tailStart));
          } on FormatException {
            // Incomplete multi-byte UTF-8 sequence at EOF; retry next poll.
            _trailingLine = null;
          }
        } else {
          _trailingLine = null;
        }
      } finally {
        raf.closeSync();
      }
    } else {
      _trailingLine = null;
    }

    _stamp = nextStamp;
    _lastMtime = stat.modified;
    return true;
  }
}

class _CachedWorkerTranscript {
  final _IncrementalJsonlReader reader = _IncrementalJsonlReader();
  final WorkerTranscriptAccumulator accumulator = WorkerTranscriptAccumulator();
  MemberTranscriptSummary? summary;
  bool? lastStale;
}

bool _sameStringSet(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

/// Watches an Antigravity conversation's `.system_generated/swarm/` directory
/// and emits a fresh [SwarmSnapshot] whenever the board, roster, plan, or
/// worker transcripts change.
class SwarmWatcher {
  SwarmWatcher({
    required this.brainDir,
    required this.swarmId,
    required this.onSnapshot,
    this.activeSince,
    this.pollInterval = const Duration(milliseconds: 1200),
  });

  static const _fsDebounce = Duration(milliseconds: 50);

  final String brainDir;
  final String swarmId;
  final void Function(SwarmSnapshot snapshot) onSnapshot;
  DateTime? activeSince;
  final Duration pollInterval;

  final Map<String, DateTime> _stoppedUntil = {};
  Timer? _timer;
  Timer? _fsDebounceTimer;
  StreamSubscription<FileSystemEvent>? _fsWatch;
  String? _lastSignature;
  bool _disposed = false;

  // Incremental disk caches so idle polls only run lightweight statSync calls
  // and appended JSONL files only decode newly written bytes.
  int _stateVersion = 0;
  int _lastPolledStateVersion = -1;
  bool _hasBuiltSnapshot = false;

  _FileStamp? _membersStamp;
  DateTime? _membersMtime;
  String _title = '';
  Map<String, Object?>? _rawRoster;
  Set<String> _rosterNames = const {};
  RosterMentionIndex _mentionIndex = RosterMentionIndex(const {});

  final _IncrementalJsonlReader _boardReader = _IncrementalJsonlReader();
  final SwarmBoardAccumulator _board = SwarmBoardAccumulator();

  _FileStamp? _planStamp;
  SwarmPlan? _plan;

  _FileStamp? _viewStamp;
  SwarmOverviewData? _overview;

  final Map<String, _CachedWorkerTranscript> _workers = {};

  /// Marks [memberName] as stopped so the UI settles immediately and ignores
  /// any trailing flush written while `session/cancel` unwinds; if the member
  /// is later re-woken with writes past the grace window, it resumes working.
  void markStopped(
    String memberName, [
    Duration grace = const Duration(seconds: 2),
  ]) {
    _stoppedUntil[memberName] = DateTime.now().add(grace);
    _lastSignature = null;
    _stateVersion++;
  }

  /// Updates the process start timestamp used to ignore stale transcripts from
  /// prior `agy` processes.
  void updateActiveSince(DateTime time) {
    activeSince = time;
    _lastSignature = null;
    _stateVersion++;
  }

  void start() {
    if (_disposed || _timer != null) return;
    _poll();
    _timer = Timer.periodic(pollInterval, (_) => _poll());
  }

  void _attachDirWatch() {
    if (_fsWatch != null || _disposed) return;
    final dir = Directory(
      p.join(brainDir, swarmId, '.system_generated', 'swarm'),
    );
    if (!dir.existsSync()) return;
    try {
      _fsWatch = dir.watch().listen(
        (_) => _scheduleFsPoll(),
        onError: (Object _) {},
      );
    } on FileSystemException {
      // Timer polling still runs.
    }
  }

  void _scheduleFsPoll() {
    if (_disposed) return;
    _fsDebounceTimer ??= Timer(_fsDebounce, () {
      _fsDebounceTimer = null;
      _poll();
    });
  }

  /// Triggers an immediate synchronous read (e.g., right after a `swarm` or
  /// `post_message` tool completes).
  void checkNow() {
    _fsDebounceTimer?.cancel();
    _fsDebounceTimer = null;
    _poll();
  }

  void _resetCaches() {
    _hasBuiltSnapshot = false;
    _membersStamp = null;
    _membersMtime = null;
    _title = '';
    _rawRoster = null;
    _rosterNames = const {};
    _mentionIndex = RosterMentionIndex(const {});
    _boardReader.reset();
    _board.reset();
    _planStamp = null;
    _plan = null;
    _viewStamp = null;
    _overview = null;
    _workers.clear();
  }

  void _poll() {
    if (_disposed) return;
    final swarmDirPath = p.join(
      brainDir,
      swarmId,
      '.system_generated',
      'swarm',
    );
    final membersFile = File(p.join(swarmDirPath, 'members.json'));
    final membersStat = membersFile.statSync();
    final nextMembersStamp = _stampOf(membersStat);
    if (nextMembersStamp == null) {
      if (_membersStamp != null) _resetCaches();
      return;
    }
    _attachDirWatch();

    var anyChanged = _lastPolledStateVersion != _stateVersion;
    var rosterNamesChanged = false;

    // 1. members.json
    if (nextMembersStamp != _membersStamp) {
      try {
        final membersJson = membersFile.readAsStringSync();
        final decoded = jsonDecode(membersJson);
        if (decoded is! Map) return;
        final parsedMembers = decoded.cast<String, Object?>();
        final nextTitle = '${parsedMembers['title'] ?? ''}'.trim();
        final nextRoster = (parsedMembers['members'] as Map? ?? const {})
            .cast<String, Object?>();
        final nextNames = nextRoster.keys.toSet();
        rosterNamesChanged = !_sameStringSet(_rosterNames, nextNames);
        _title = nextTitle;
        _rawRoster = nextRoster;
        if (rosterNamesChanged) {
          _rosterNames = nextNames;
          _mentionIndex = RosterMentionIndex(nextNames);
        }
        _membersStamp = nextMembersStamp;
        _membersMtime = membersStat.modified;
        anyChanged = true;

        // Drop cached transcripts for removed conversations.
        final activeConvIds = <String>{};
        for (final entry in nextRoster.values) {
          if (entry is Map) {
            final convId = entry['conversation_id'];
            if (convId is String && convId.isNotEmpty) {
              activeConvIds.add(convId);
            }
          }
        }
        _workers.removeWhere((convId, _) => !activeConvIds.contains(convId));
      } on Object {
        // Half-written members.json; retry next poll.
        return;
      }
    }

    final rawRoster = _rawRoster;
    final membersMtime = _membersMtime;
    if (rawRoster == null || membersMtime == null) return;

    // 2. board.jsonl (incremental append-only read; full re-read only if roster
    // names changed so @mentions resolve against new members).
    final boardFile = File(p.join(swarmDirPath, 'board.jsonl'));
    if (rosterNamesChanged) {
      _boardReader.reset();
      _board.reset();
    }
    try {
      if (_boardReader.sync(
        boardFile,
        onReset: _board.reset,
        onCommittedChunk: (chunk) => _board.addContent(chunk, _mentionIndex),
      )) {
        anyChanged = true;
      }
    } on FileSystemException {
      // Being written; retry next poll.
    }

    // 3. plan.json
    final planFile = File(p.join(swarmDirPath, 'plan.json'));
    final nextPlanStamp = _stampOf(planFile.statSync());
    if (nextPlanStamp != _planStamp) {
      if (nextPlanStamp == null) {
        _plan = null;
        _planStamp = null;
        anyChanged = true;
      } else {
        try {
          final raw = planFile.readAsStringSync();
          if (raw.trim().isEmpty) {
            _plan = null;
          } else if (jsonDecode(raw) case final Map pMap) {
            _plan = SwarmPlan.fromJson(pMap.cast<String, Object?>());
          }
          _planStamp = nextPlanStamp;
          anyChanged = true;
        } on Object {
          // Ignore half-written plan.json; retry next poll.
        }
      }
    }

    // 4. view.json
    final viewFile = File(p.join(swarmDirPath, 'view.json'));
    final nextViewStamp = _stampOf(viewFile.statSync());
    if (nextViewStamp != _viewStamp) {
      if (nextViewStamp == null) {
        _overview = null;
        _viewStamp = null;
        anyChanged = true;
      } else {
        try {
          final raw = viewFile.readAsStringSync();
          if (raw.trim().isEmpty) {
            _overview = null;
          } else if (jsonDecode(raw) case final Map vMap) {
            _overview = SwarmOverviewData.fromJson(
              vMap.cast<String, Object?>(),
            );
          }
          _viewStamp = nextViewStamp;
          anyChanged = true;
        } on Object {
          // Ignore half-written view.json; retry next poll.
        }
      }
    }

    // 5. Worker transcripts (stat-cached + byte-offset incremental read).
    final transcripts = <String, MemberTranscriptSummary>{};
    final stoppedMembers = <String>{};
    for (final MapEntry(key: memberKey, value: entry) in rawRoster.entries) {
      if (entry is! Map) continue;
      final name = memberKey;
      final convId = entry['conversation_id'];
      if (convId is! String || convId.isEmpty) continue;
      final tFile = File(
        p.join(
          brainDir,
          convId,
          '.system_generated',
          'logs',
          'transcript.jsonl',
        ),
      );
      final cached = _workers.putIfAbsent(convId, _CachedWorkerTranscript.new);
      var workerChanged = false;
      try {
        workerChanged = cached.reader.sync(
          tFile,
          onReset: cached.accumulator.reset,
          onCommittedChunk: cached.accumulator.addContent,
        );
      } on FileSystemException {
        // Being written; reuse previous summary and retry next poll.
      }

      final stopCutoff = _stoppedUntil[name];
      final mtime = cached.reader.lastMtime;
      if (!cached.reader.exists || mtime == null) {
        if (stopCutoff != null) stoppedMembers.add(name);
        if (workerChanged) {
          cached.summary = null;
          cached.lastStale = null;
          anyChanged = true;
        }
        continue;
      }

      if (stopCutoff != null && !mtime.isAfter(stopCutoff)) {
        stoppedMembers.add(name);
      }
      final stale = activeSince != null && mtime.isBefore(activeSince!);
      if (workerChanged ||
          cached.summary == null ||
          cached.lastStale != stale) {
        cached.summary = cached.accumulator.buildSummary(
          stale: stale,
          trailingLine: cached.reader.trailingLine,
        );
        cached.lastStale = stale;
        anyChanged = true;
      }
      if (cached.summary case final summary?) {
        transcripts[convId] = summary;
      }
    }

    // Fast path: nothing on disk and no watcher state changed since last build.
    if (!anyChanged && _hasBuiltSnapshot) return;

    _lastPolledStateVersion = _stateVersion;
    _hasBuiltSnapshot = true;

    final allowUnwrittenWorking =
        activeSince == null || !membersMtime.isBefore(activeSince!);
    final effectiveBoard = _board.cloneWithTrailingLine(
      _boardReader.trailingLine,
      _mentionIndex,
    );
    final snapshot = buildSwarmSnapshotFromParsed(
      swarmId: swarmId,
      title: _title,
      rawRoster: rawRoster,
      board: effectiveBoard,
      brainDir: brainDir,
      plan: _plan,
      overview: _overview,
      transcripts: transcripts,
      stoppedMembers: stoppedMembers,
      allowUnwrittenWorking: allowUnwrittenWorking,
    );

    // Clear stop overrides once a member has woken up again past its cutoff.
    for (final m in snapshot.members) {
      if (m.status == SwarmMemberStatus.working) {
        _stoppedUntil.remove(m.name);
      }
    }
    final sig = jsonEncode({
      'title': snapshot.title,
      'head': snapshot.headSeq,
      'msgs': snapshot.messages.length,
      'members': [
        for (final m in snapshot.members)
          [
            m.name,
            m.status.name,
            m.model,
            m.stepsCount,
            m.postsCount,
            m.unreadCount,
            m.currentActivity,
            m.failure,
            m.steps.length,
            m.steps.lastOrNull?.detail?.length,
          ],
      ],
      'plan': snapshot.plan?.toJson(),
      'overview': snapshot.overview?.toJson(),
    });
    if (sig == _lastSignature) return;
    _lastSignature = sig;
    onSnapshot(snapshot);
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _fsDebounceTimer?.cancel();
    _fsDebounceTimer = null;
    unawaited(_fsWatch?.cancel());
    _fsWatch = null;
    _resetCaches();
  }
}
