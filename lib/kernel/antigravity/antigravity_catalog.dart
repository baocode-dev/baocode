import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../remote/remote_location.dart';
import '../agent_kernel.dart';
import 'agy_runtime.dart';

/// The conversations agy keeps (the user's terminal's among them), by
/// project: this machine's alone, it runs nowhere else.
class AntigravityCatalog implements SessionCatalog, ChangingCatalog {
  const AntigravityCatalog();

  static AgyRuntime get _runtime => AgyRuntime.local;

  /// Listed lately; or, before agy is up to list (seconds), as last
  /// listed the run before.
  static List<SessionRecord>? _listed;
  static DateTime? _listedAt;
  static Future<List<SessionRecord>>? _listing;

  static const _fresh = Duration(seconds: 15);

  static final _Changes _changes = _Changes();

  @override
  Listenable get changes => _changes;

  static Future<List<SessionRecord>> _sessions() {
    final at = _listedAt;
    if (_listed case final listed?
        when at != null && DateTime.now().difference(at) < _fresh) {
      return Future.value(listed);
    }
    final listing = _listing ??= _runtime
        .sessions()
        .then((sessions) {
          _listed = sessions;
          _listedAt = DateTime.now();
          return sessions;
        })
        .whenComplete(() => _listing = null);
    if (_listed == null) {
      if (_runtime.lastSessions case final kept?) {
        // Shown at once; told of the listing when it comes.
        _listed = kept;
        unawaited(listing.then((_) => _changes.tell(), onError: (_) {}));
        return Future.value(kept);
      }
    }
    return listing;
  }

  /// Lists anew next time (a conversation started or deleted).
  static void forget() {
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
    _listed = null;
    forget();
  }
}

class _Changes extends ChangeNotifier {
  void tell() => notifyListeners();
}
