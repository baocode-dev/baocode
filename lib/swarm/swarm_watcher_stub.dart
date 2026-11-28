import 'swarm_model.dart';

SwarmSnapshot? readSwarmSnapshotSync(
  String brainDir,
  String swarmId, {
  DateTime? activeSince,
  Map<String, DateTime> stoppedUntil = const {},
}) => null;

Future<List<SwarmWorkerStep>> readSwarmWorkerTranscript(
  String brainDir,
  String conversationId,
) async => const [];

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

  void markStopped(
    String memberName, [
    Duration grace = const Duration(seconds: 2),
  ]) {}
  void updateActiveSince(DateTime time) {}
  void start() {}
  void checkNow() {}
  void dispose() {}
}
