import '../agent_kernel.dart';

/// No local sessions on the web.
class ClaudeStorage implements SessionCatalog {
  const ClaudeStorage();

  @override
  Future<List<ProjectRecord>> projects() async => const [];

  @override
  Future<List<SessionRecord>> sessionsIn(String cwd) async => const [];

  @override
  Future<void> delete(String id) async {}

  static Future<List<Map<String, Object?>>> read(SessionRecord session) async =>
      const [];
}
