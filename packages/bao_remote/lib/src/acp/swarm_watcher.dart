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
          p.join(brainDir, convId, '.system_generated', 'logs', 'transcript.jsonl'),
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

  final String brainDir;
  final String swarmId;
  final void Function(SwarmSnapshot snapshot) onSnapshot;
  DateTime? activeSince;
  final Duration pollInterval;

  final Map<String, DateTime> _stoppedUntil = {};
  Timer? _timer;
  StreamSubscription<FileSystemEvent>? _fsWatch;
  String? _lastSignature;
  bool _disposed = false;

  /// Marks [memberName] as stopped so the UI settles immediately and ignores
  /// any trailing flush written while `session/cancel` unwinds; if the member
  /// is later re-woken with writes past the grace window, it resumes working.
  void markStopped(
    String memberName, [
    Duration grace = const Duration(seconds: 2),
  ]) {
    _stoppedUntil[memberName] = DateTime.now().add(grace);
    _lastSignature = null;
  }

  /// Updates the process start timestamp used to ignore stale transcripts from
  /// prior `agy` processes.
  void updateActiveSince(DateTime time) {
    activeSince = time;
    _lastSignature = null;
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
      _fsWatch = dir.watch().listen((_) => _poll(), onError: (Object _) {});
    } on FileSystemException {
      // Timer polling still runs.
    }
  }

  /// Triggers an immediate read (e.g., right after a `swarm` or `post_message`
  /// tool completes).
  void checkNow() => _poll();

  void _poll() {
    if (_disposed) return;
    _attachDirWatch();
    final snapshot = readSwarmSnapshotSync(
      brainDir,
      swarmId,
      activeSince: activeSince,
      stoppedUntil: _stoppedUntil,
    );
    if (snapshot == null) return;
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
    unawaited(_fsWatch?.cancel());
    _fsWatch = null;
  }
}
