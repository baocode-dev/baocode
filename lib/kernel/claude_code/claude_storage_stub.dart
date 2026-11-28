import 'package:bao_remote/claude.dart' show ClaudeHistoryPage, IndexedTurnHit;

import '../agent_kernel.dart';

/// No local sessions on the web.
class ClaudeStorage implements SessionCatalog, MovesSessions {
  const ClaudeStorage();

  @override
  Future<int> moveSessions(String from, String to) =>
      throw UnsupportedError('No local sessions on the web');

  @override
  Future<List<ProjectRecord>> projects() async => const [];

  @override
  Future<List<SessionRecord>> sessionsIn(String cwd) async => const [];

  @override
  Future<void> delete(String id) async {}

  Future<List<Map<String, Object?>>> goal(String id) async => const [];

  Future<String> fork(
    String id,
    String into, {
    String? before,
    String? title,
  }) => throw UnsupportedError('No local sessions on the web');

  static Future<List<Map<String, Object?>>> read(SessionRecord session) async =>
      const [];

  static Future<ClaudeHistoryPage> readPage(
    SessionRecord session, {
    required int turns,
    String? before,
    String? until,
  }) async => const ClaudeHistoryPage([]);

  static Future<List<IndexedTurnHit>> searchEarlier(
    SessionRecord session,
    String patternSource, {
    required bool caseSensitive,
    String? before,
  }) async => const [];
}
