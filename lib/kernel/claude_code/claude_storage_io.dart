import 'package:bao_remote/local.dart';
import 'package:path/path.dart' as p;

import '../../platform/data_dir.dart';
import '../agent_kernel.dart';

/// Claude Code's own record of its sessions on this machine (see
/// [ClaudeSessions]).
class ClaudeStorage implements SessionCatalog {
  const ClaudeStorage({this.configDir, this.tempDir, this.cacheFile});

  /// Where Claude Code keeps its state; by default `BAOCODE_CLAUDE_DATA_PATH`
  /// as the login shell has it, else `CLAUDE_CONFIG_DIR`, else
  /// `<home>/.claude`.
  final String? configDir;

  /// Where it keeps what a session's tasks print (`claude-<uid>/`); the
  /// system's temporary folder by default.
  final String? tempDir;

  /// Where what was made of each session file is kept between runs; in the
  /// app's cache folder by default.
  final String? cacheFile;

  ClaudeSessions get _sessions => ClaudeSessions(
    configDir: configDir,
    tempDir: tempDir,
    cacheFile:
        cacheFile ??
        p.join(DataDirectory.current.cacheDir, 'claude-sessions.json'),
  );

  @override
  Future<void> delete(String id) => _sessions.delete(id);

  @override
  Future<List<ProjectRecord>> projects() async => [
    for (final project in await _sessions.projects()) projectRecord(project),
  ];

  @override
  Future<List<SessionRecord>> sessionsIn(String cwd) async {
    final all = await projects();
    return all.where((p) => p.path == cwd).firstOrNull?.sessions ?? const [];
  }

  /// What the session [id] kept of its goal (see [ClaudeSessions.goal]).
  Future<List<Map<String, Object?>>> goal(String id) => _sessions.goal(id);

  /// The session's conversation along the branch it ended on.
  static Future<List<Map<String, Object?>>> read(SessionRecord session) {
    final path = session.path;
    if (path == null) return Future.value(const []);
    return ClaudeSessions.read(path);
  }

  /// [project] as the kernels list it, its folder and sessions' given by
  /// [location] (on another machine, see host.dart).
  static ProjectRecord projectRecord(
    ClaudeProjectSummary project, {
    String Function(String path)? location,
  }) => ProjectRecord(
    path: location?.call(project.path) ?? project.path,
    sessions: [
      for (final session in project.sessions)
        SessionRecord(
          id: session.id,
          title: session.title,
          updatedAt: session.updatedAt,
          cwd: location?.call(session.cwd) ?? session.cwd,
          path: session.path,
        ),
    ],
  );
}
