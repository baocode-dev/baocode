import '../../remote/remote_location.dart';
import '../agent_kernel.dart';
import 'agy_runtime.dart';

/// The conversations agy keeps (the user's terminal's among them), by
/// project: this machine's alone, it runs nowhere else.
class AntigravityCatalog implements SessionCatalog {
  const AntigravityCatalog();

  static AgyRuntime get _runtime => AgyRuntime.local;

  /// Listed lately: each listing starts agy.
  static List<SessionRecord>? _listed;
  static DateTime? _listedAt;
  static Future<List<SessionRecord>>? _listing;

  static const _fresh = Duration(seconds: 15);

  static Future<List<SessionRecord>> _sessions() {
    final at = _listedAt;
    if (_listed case final listed?
        when at != null && DateTime.now().difference(at) < _fresh) {
      return Future.value(listed);
    }
    return _listing ??= _runtime
        .sessions()
        .then((sessions) {
          _listed = sessions;
          _listedAt = DateTime.now();
          return sessions;
        })
        .whenComplete(() => _listing = null);
  }

  /// Lists anew next time (a conversation started or deleted).
  static void forget() {
    _listed = null;
    _listedAt = null;
  }

  @override
  Future<List<ProjectRecord>> projects() async {
    final byPath = <String, List<SessionRecord>>{};
    for (final session in await _sessions()) {
      byPath.putIfAbsent(session.cwd, () => []).add(session);
    }
    final projects = [
      for (final MapEntry(key: path, value: sessions) in byPath.entries)
        ProjectRecord(
          path: path,
          sessions: sessions
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
        ),
    ];
    projects.sort((a, b) => b.updatedAt!.compareTo(a.updatedAt!));
    return projects;
  }

  @override
  Future<List<SessionRecord>> sessionsIn(String cwd) async {
    if (RemoteLocation.isRemote(cwd)) return const [];
    return [
      for (final session in await _sessions())
        if (session.cwd == cwd) session,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  @override
  Future<void> delete(String id) async {
    await _runtime.delete(id);
    forget();
  }
}
