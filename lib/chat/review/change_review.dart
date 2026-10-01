import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../chat_models.dart';
import 'review_store.dart';

/// A file the agent changed: what it was before (kept, the file as it is
/// becomes that), what the agent left, and what is there now.
class _Entry {
  _Entry(this.base);

  ReviewBlob? base;
  ReviewBlob? after;
  ReviewBlob? current;

  /// The agent said it edited it (not, say, by a command).
  bool reported = false;
  bool shared = false;
  bool conflict = false;

  /// Whether it differs from what was there before.
  bool get pending => switch ((base, current)) {
    (null, null) => false,
    (final base?, final current) => !base.sameContent(current),
    _ => true,
  };

  Map<String, Object?> toJson() => {
    'base': base?.toJson(),
    'after': after?.toJson(),
    'current': current?.toJson(),
    'reported': reported,
    'shared': shared,
    'conflict': conflict,
  };

  static _Entry fromJson(Map<String, Object?> json) =>
      _Entry(ReviewBlob.fromJson(json['base']))
        ..after = ReviewBlob.fromJson(json['after'])
        ..current = ReviewBlob.fromJson(json['current'])
        ..reported = json['reported'] == true
        ..shared = json['shared'] == true
        ..conflict = json['conflict'] == true;
}

/// What an agent changed in its project, held against what was there
/// before, for the user to keep or undo file by file: the review behind
/// Keep and Undo.
///
/// The project is snapshotted ([ReviewStore]) before a turn and as the
/// agent edits; what differs from one snapshot to the next while it works
/// is its change. Whatever else changes in between (the user, between
/// turns) is not, and Undo carries it over (a three-way merge) rather than
/// write over it: where it cannot, the file is left as it is and marked.
///
/// Kept, a change is only no longer listed: nothing is written, staged or
/// committed. Undone, the file is put back.
class ChangeReview extends ChangeNotifier {
  ChangeReview(this._store);

  /// The review of the project at [root], continuing what [session] left;
  /// null where there can be none (see [ReviewStore.open]).
  static Future<ChangeReview?> open(String root, {String? session}) async {
    final store = await ReviewStore.open(root);
    if (store == null) return null;
    if (session == null) return ChangeReview(store);
    return resume(store, session);
  }

  /// The review over [store], with the changes [session] left pending.
  static Future<ChangeReview> resume(ReviewStore store, String session) async {
    final review = ChangeReview(store);
    await review._load(session);
    return review;
  }

  final ReviewStore _store;

  String get root => _store.root;

  /// The latest snapshot, as a tree; null before the first.
  String? _snapshot;

  /// By path relative to [root].
  final Map<String, _Entry> _entries = {};

  /// Edits reported since the last look, by relative path.
  final Map<String, FileChange> _reported = {};

  /// Edits reported that the snapshots do not see (ignored files, files
  /// too large, outside the project), by absolute path: listed, to be
  /// kept, never undone.
  final Map<String, FileChange> _unseen = {};

  List<FileChange> _changes = const [];

  /// The pending changes, one per file, with absolute paths.
  List<FileChange> get changes => _changes;

  /// Why it stopped: a snapshot failed (Git went away, the project grew
  /// too large). Its changes are then no longer known.
  String? get failure => _failure;
  String? _failure;

  /// The session it is kept under, once known.
  String? get session => _session;
  String? _session;
  set session(String? id) {
    if (id == null || id == _session) return;
    _session = id;
    unawaited(_enqueue(_persist));
  }

  // --- Agents at work in the same project -------------------------------------

  static final Map<String, Set<ChangeReview>> _working = {};

  bool _isWorking = false;

  /// Another agent worked in the project since the last look.
  bool _overlap = false;

  Set<ChangeReview> get _workingHere => _working.putIfAbsent(root, () => {});

  /// Whether its agent is at work: changes seen while another one in the
  /// project is too are marked [FileChange.shared] (unless its agent said
  /// it made them).
  set working(bool working) {
    if (working == _isWorking) return;
    _isWorking = working;
    final others = _workingHere;
    if (working) {
      if (others.isNotEmpty) _overlap = true;
      for (final other in others) {
        other._overlap = true;
      }
      others.add(this);
    } else {
      others.remove(this);
    }
  }

  // --- Looking ----------------------------------------------------------------

  Future<void> _queue = Future.value();
  bool _disposed = false;

  /// Runs [operation] after those before it; a failure stops the review.
  Future<void> _enqueue(Future<void> Function() operation) =>
      _queue = _queue.then((_) async {
        if (_disposed || _failure != null) return;
        try {
          await operation();
        } on Object catch (error) {
          abandon('$error');
        }
      });

  /// Stops it for [reason]: its changes are no longer known.
  void abandon(String reason) {
    if (_failure != null) return;
    _failure = reason;
    _changes = const [];
    if (!_disposed) notifyListeners();
  }

  /// Snapshots the project before a turn: what changed since the last look
  /// was not the agent.
  Future<void> begin() => _enqueue(() => _look(agent: false));

  /// Snapshots the project as the agent works: what changed since the last
  /// look was the agent. Only the files reported since, unless [full].
  Future<void> observe({bool full = true}) => _enqueue(
    () => _look(agent: true, paths: full ? null : _reported.keys.toList()),
  );

  /// The agent reported an edit to [change]'s file; seen at the next
  /// [observe].
  void report(FileChange change) {
    final path = _relative(change.path);
    if (path != null) {
      _reported[path] = change;
      return;
    }
    // Outside the project: never in a snapshot.
    final absolute = _absolute(change.path);
    _unseen[absolute] = _merged(_unseen[absolute], change, absolute);
    unawaited(_enqueue(_refresh));
  }

  static FileChange _merged(
    FileChange? before,
    FileChange change,
    String path,
  ) => FileChange(
    path: path,
    added: (before?.added ?? 0) + change.added,
    removed: (before?.removed ?? 0) + change.removed,
    tracked: false,
  );

  Future<void> _look({required bool agent, List<String>? paths}) async {
    if (paths != null && paths.isEmpty) return;
    final next = await _store.snapshot(paths: paths);
    final previous = _snapshot;
    _snapshot = next;
    if (previous != null) {
      for (final change in await _store.diff(previous, next)) {
        // Another repository inside the project: its own business.
        if (change.before?.mode == '160000' || change.after?.mode == '160000') {
          continue;
        }
        var entry = _entries[change.path];
        if (agent) {
          entry ??= _entries[change.path] = _Entry(change.before);
          entry
            ..after = change.after
            ..current = change.after
            ..conflict = false;
          if (_overlap && !entry.reported) entry.shared = true;
        } else if (entry != null) {
          entry
            ..current = change.after
            ..conflict = false;
        }
      }
    }
    if (agent) {
      for (final MapEntry(key: path, value: change) in [..._reported.entries]) {
        if (paths != null && !paths.contains(path)) continue;
        _reported.remove(path);
        if (_entries[path] case final entry?) {
          entry
            ..reported = true
            ..shared = false;
        } else if (await _store.exists(path) &&
            !await _store.contains(next, path)) {
          final absolute = _absolute(path);
          _unseen[absolute] = _merged(_unseen[absolute], change, absolute);
        }
      }
      if (paths == null) _overlap = _workingHere.any((r) => r != this);
    }
    _entries.removeWhere((_, entry) => !entry.pending);
    await _refresh();
    await _persist();
  }

  /// [changes] anew, with their line counts.
  Future<void> _refresh() async {
    final snapshot = _snapshot;
    Map<String, ({int added, int removed})?> counts = const {};
    if (snapshot != null && _entries.isNotEmpty) {
      try {
        final base = await _store.overlay(snapshot, {
          for (final MapEntry(key: path, value: entry) in _entries.entries)
            path: entry.base,
        });
        counts = await _store.lineCounts(base, snapshot);
      } on Object {
        // Listed without their counts.
      }
    }
    final paths = _entries.keys.toList()..sort();
    _changes = [
      for (final path in paths)
        if (_entries[path] case final entry?)
          FileChange(
            path: _absolute(path),
            added: counts[path]?.added ?? 0,
            removed: counts[path]?.removed ?? 0,
            binary: counts.containsKey(path) && counts[path] == null,
            kind: entry.base == null
                ? FileChangeKind.added
                : entry.current == null
                ? FileChangeKind.deleted
                : FileChangeKind.modified,
            shared: entry.shared,
            conflict: entry.conflict,
          ),
      ..._unseen.values,
    ];
    if (!_disposed) notifyListeners();
  }

  // --- Keep and Undo -----------------------------------------------------------

  /// Keeps the changes to [paths] (absolute): they are no longer listed.
  Future<void> keep(Iterable<String> paths) {
    final kept = paths.toList();
    return _enqueue(() async {
      for (final path in kept) {
        _unseen.remove(path);
        _entries.remove(_relative(path));
      }
      await _refresh();
      await _persist();
    });
  }

  Future<void> keepAll() => _enqueue(() async {
    _unseen.clear();
    _entries.clear();
    await _refresh();
    await _persist();
  });

  /// Puts the files at [paths] (absolute) back as they were before the
  /// agent changed them, keeping what changed since where it can (else the
  /// file stays, marked [FileChange.conflict]).
  Future<void> undo(Iterable<String> paths) {
    final wanted = paths.toList();
    return _enqueue(() async {
      final undone = <String>[];
      for (final absolute in wanted) {
        final path = _relative(absolute);
        final entry = path == null ? null : _entries[path];
        if (path == null || entry == null) continue;
        try {
          if (await _undo(path, entry)) {
            undone.add(path);
          } else {
            entry.conflict = true;
          }
        } on Object {
          entry.conflict = true;
        }
      }
      for (final path in undone) {
        _entries.remove(path);
      }
      // What it wrote is not the agent's.
      await _look(agent: false, paths: undone);
      if (undone.isEmpty) await _refresh();
      await _persist();
    });
  }

  Future<void> undoAll() =>
      undo([for (final path in _entries.keys) _absolute(path)]);

  /// Whether [path] is back as it was.
  Future<bool> _undo(String path, _Entry entry) async {
    final now = await _store.current(path);
    final base = entry.base;
    final after = entry.after;
    // Already back.
    if (base == null ? now == null : base.sameContent(now)) return true;
    // As the agent left it: put back what was.
    if (now == null ? after == null : now.sameContent(after)) {
      await _store.restore(path, base);
      return true;
    }
    // Changed since: the agent's change taken out of it.
    if (now != null && after != null && base != null && !now.isLink) {
      final merged = await _store.merge(path, after, base);
      if (merged == null) return false;
      await _store.write(path, merged);
      return true;
    }
    return false;
  }

  /// The text of [path] (absolute) before the agent changed it: empty for
  /// a file it created; null when it is not in the snapshots.
  Future<String> Function()? original(String path) {
    final relative = _relative(path);
    if (relative == null || !_entries.containsKey(relative)) return null;
    return () async {
      final base = _entries[relative]?.base;
      if (base == null) return '';
      return utf8.decode(await _store.read(base), allowMalformed: true);
    };
  }

  // --- Keeping it between runs ----------------------------------------------

  Future<void> _persist() async {
    final session = _session;
    final snapshot = _snapshot;
    if (session == null || snapshot == null) return;
    if (_entries.isEmpty && _unseen.isEmpty) {
      await _store.forget(session);
      return;
    }
    await _store.save(
      session,
      jsonEncode({
        'version': 1,
        'snapshot': snapshot,
        'entries': {
          for (final MapEntry(key: path, value: entry) in _entries.entries)
            path: entry.toJson(),
        },
        'unseen': [
          for (final change in _unseen.values)
            {
              'path': change.path,
              'added': change.added,
              'removed': change.removed,
            },
        ],
      }),
      trees: [snapshot],
      blobs: [
        for (final entry in _entries.values) ...[?entry.base, ?entry.after],
      ],
    );
  }

  Future<void> _load(String session) async {
    _session = session;
    try {
      final data = await _store.load(session);
      if (data == null) return;
      final json = jsonDecode(data);
      if (json is! Map<String, Object?> || json['version'] != 1) return;
      _snapshot = json['snapshot'] as String?;
      if (json['entries'] case final Map<String, Object?> entries) {
        for (final MapEntry(key: path, value: entry) in entries.entries) {
          if (entry is Map<String, Object?>) {
            _entries[path] = _Entry.fromJson(entry);
          }
        }
      }
      if (json['unseen'] case final List<Object?> unseen) {
        for (final change in unseen) {
          if (change case {
            'path': final String path,
            'added': final int added,
            'removed': final int removed,
          }) {
            _unseen[path] = FileChange(
              path: path,
              added: added,
              removed: removed,
              tracked: false,
            );
          }
        }
      }
      await _refresh();
    } on Object {
      // Begun anew.
      _snapshot = null;
      _entries.clear();
      _unseen.clear();
    }
  }

  // --- Paths ------------------------------------------------------------------

  /// [path] (absolute, or relative to [root]) relative to [root], with
  /// `/`; null outside it.
  String? _relative(String path) {
    final absolute = _absolute(path);
    if (!p.isWithin(root, absolute)) return null;
    return p.split(p.relative(absolute, from: root)).join('/');
  }

  String _absolute(String path) => p.normalize(
    p.isAbsolute(path) ? path : p.joinAll([root, ...path.split('/')]),
  );

  /// Drops what it kept between runs, once what is under way is done: the
  /// conversation is gone.
  Future<void> discard() {
    final session = _session;
    _session = null;
    if (session == null) return Future.value();
    return _queue = _queue.then(
      (_) => _store.forget(session).catchError((Object _) {}),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    working = false;
    super.dispose();
  }
}
