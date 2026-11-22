import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../remote/remote_location.dart';
import '../agent_kernel.dart';
import 'agy_runtime.dart';
import 'antigravity_translator.dart';

/// The conversations agy keeps (the user's terminal's among them), by
/// project: this machine's alone, it runs nowhere else. Listed from its
/// language server (`JetboxSubscribeToSummaries`, its first frame).
class AntigravityCatalog implements SessionCatalog, ChangingCatalog {
  const AntigravityCatalog();

  static AgyRuntime get _runtime => AgyRuntime.local;

  /// Listed lately; or, before agy is up to list (seconds), as last
  /// listed the run before.
  static List<SessionRecord>? _listed;
  static DateTime? _listedAt;
  static Future<List<SessionRecord>>? _listing;

  static const _fresh = Duration(seconds: 15);
  static const _wait = Duration(seconds: 30);

  static final _Changes _changes = _Changes();

  @override
  Listenable get changes => _changes;

  static Future<List<SessionRecord>> _sessions() {
    final at = _listedAt;
    if (_listed case final listed?
        when at != null && DateTime.now().difference(at) < _fresh) {
      return Future.value(listed);
    }
    final listing = _listing ??= _list()
        .then((sessions) {
          _listed = sessions;
          _listedAt = DateTime.now();
          _runtime.lastSessions = sessions;
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

  static Future<List<SessionRecord>> _list() async {
    if (await _runtime.locate() == null) return const [];
    final server = await _runtime.server();
    final first = await server
        .stream('JetboxSubscribeToSummaries', const {})
        .first
        .timeout(_wait);
    return summariesOf(first, dataDir: _runtime.dataDir);
  }

  /// The conversations of a summaries frame: each with its project (its
  /// first workspace), named as annotated, else by its first message.
  /// Subagents' conversations (those with a parent) are left out.
  @visibleForTesting
  static List<SessionRecord> summariesOf(
    Map<String, Object?> frame, {
    required String dataDir,
  }) {
    final updates = switch (frame['updates']) {
      final Map updates => updates,
      _ => const {},
    };
    final records = <SessionRecord>[];
    for (final MapEntry(key: id, value: summary) in updates.entries) {
      if (id is! String || summary is! Map) continue;
      final metadata = _map(summary['trajectoryMetadata']);
      if (metadata['parentConversationId'] case final String parent
          when parent.isNotEmpty) {
        continue;
      }
      final workspace = switch (summary['workspaces']) {
        [{'workspaceFolderAbsoluteUri': final String uri}, ...] => uri,
        _ => switch (metadata['workspaceUris']) {
          [final String uri, ...] => uri,
          _ => null,
        },
      };
      if (workspace == null) continue;
      final cwd = _pathOf(workspace);
      final annotations = _map(summary['annotations']);
      final title = switch (annotations['title']) {
        final String title when title.trim().isNotEmpty => title.trim(),
        _ => _titleOf(summary['summary'] as String? ?? ''),
      };
      final updatedAt =
          _time(summary['lastModifiedTime']) ??
          _time(summary['lastUserInputTime']) ??
          _time(summary['createdTime']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      records.add(
        SessionRecord(
          id: id,
          title: title,
          updatedAt: updatedAt,
          cwd: cwd,
          path: p.join(dataDir, 'conversations', '$id.db'),
        ),
      );
    }
    return records;
  }

  /// A conversation's name from its first message: without the app's
  /// notes to agy, and its `/plan`.
  static String _titleOf(String summary) {
    final plain = AntigravityTranslator.withoutReminders(summary)
        .replaceFirst(RegExp(r'^/plan\s*'), '')
        .trim();
    return plain.split('\n').first.trim();
  }

  static Map<String, Object?> _map(Object? value) => switch (value) {
    final Map map => map.cast<String, Object?>(),
    _ => const {},
  };

  static DateTime? _time(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;

  static String _pathOf(String uri) {
    if (!uri.startsWith('file:')) return uri;
    try {
      final path = Uri.parse(uri).toFilePath();
      return path.length > 1 && path.endsWith(p.separator)
          ? path.substring(0, path.length - 1)
          : path;
    } on Object {
      return Uri.decodeFull(uri.replaceFirst(RegExp('^file://'), ''));
    }
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
