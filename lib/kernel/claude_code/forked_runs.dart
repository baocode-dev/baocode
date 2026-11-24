import 'forked_runs_stub.dart'
    if (dart.library.io) 'forked_runs_io.dart'
    as platform;

/// A skill run from a slash command in a subagent of its own (`/code-review`,
/// `context: fork`): the CLI sends nothing of it until it is done, but
/// writes its messages as it goes, in the session's `subagents/` folder.
/// Read from there, they show in its card as it works (#1131).
abstract interface class ForkedRuns {
  /// Follows the run that session [sessionId] (of a project in [cwd], its
  /// CLI started with [env] besides the machine's) starts now: each line
  /// its subagent writes, to [onLine], from the first.
  ForkedRun watch({
    required String cwd,
    required String sessionId,
    Map<String, String>? env,
    required void Function(Map<String, Object?> line) onLine,
  });
}

/// A run followed ([ForkedRuns.watch]).
abstract interface class ForkedRun {
  /// The run is done: what is left of its lines is read, then no more.
  void finish();

  /// No more lines, at once.
  void cancel();
}

/// This machine's; null where there are no files (the web).
ForkedRuns? forkedRunsHere() => platform.forkedRunsHere();
