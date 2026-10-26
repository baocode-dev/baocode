import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../remote/remote_location.dart';
import '../chat_models.dart';
import 'review_store.dart';
import 'unpatch.dart';

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

  /// Not in the snapshots (ignored, too large, or none taken): looked at
  /// file by file, what it was before as the agent told.
  bool loose = false;

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
    'loose': loose,
  };

  static _Entry fromJson(Map<String, Object?> json) =>
      _Entry(ReviewBlob.fromJson(json['base']))
        ..after = ReviewBlob.fromJson(json['after'])
        ..current = ReviewBlob.fromJson(json['current'])
        ..reported = json['reported'] == true
        ..shared = json['shared'] == true
        ..conflict = json['conflict'] == true
        ..loose = json['loose'] == true;
}

/// What an agent changed in its project, held against what was there
/// before, for the user to keep or undo file by file: the review behind
/// Keep and Undo.
///
/// The project is snapshotted ([ReviewStore]) before a turn and as the
/// agent edits; what differs from one snapshot to the next while it works
/// is its change, however it made it (an edit, a command). Whatever else
/// changes in between (the user, between turns) is not, and Undo carries
/// it over (a three-way merge) rather than write over it: where it cannot,
/// the file is left as it is and marked.
///
/// A file the snapshots leave out (ignored, too large; any, in a project
/// too large to snapshot) that the agent reports it edited is held
/// against what it was as the agent tells ([FileOriginal]), as is one
/// outside the project (in a worktree beside it, say); without that, it is
/// listed, to be kept and not undone.
///
/// Kept, a change is only no longer listed: nothing is written, staged or
/// committed. Undone, the file is put back.
class ChangeReview extends ChangeNotifier {
  /// Its files' paths spelled as [paths] has them: this machine's way
  /// when null.
  ///
  /// [realRoot] is [root] with its links resolved, where that is another
  /// path: the agent may tell the project's files by it (Claude Code does:
  /// macOS's `/tmp` is `/private/tmp`), and they are the project's.
  ChangeReview(this._store, {p.Context? paths, this.realRoot})
    : _paths = paths ?? p.context;

  /// The review of the project at [root], continuing what [session] left;
  /// null where there can be none (see [openReviewStore]).
  static Future<ChangeReview?> open(String root, {String? session}) async {
    final store = await openReviewStore(root);
    if (store == null) return null;
    // A remote project's paths are its host's (POSIX), whatever this
    // machine spells its own with.
    final paths = RemoteLocation.pathsOf(root);
    final realRoot = await realRootOf(root);
    if (session == null) {
      return ChangeReview(store, paths: paths, realRoot: realRoot);
    }
    return resume(store, session, paths: paths, realRoot: realRoot);
  }

  /// The review over [store], with the changes [session] left pending.
  static Future<ChangeReview> resume(
    ReviewStore store,
    String session, {
    p.Context? paths,
    String? realRoot,
  }) async {
    final review = ChangeReview(store, paths: paths, realRoot: realRoot);
    await review._load(session);
    return review;
  }

  final ReviewStore _store;
  final p.Context _paths;

  /// [root] with its links resolved, where that is another path.
  final String? realRoot;

  /// How its files' paths are spelled.
  p.Context get paths => _paths;

  String get root => _store.root;

  /// The latest snapshot, as a tree; null before the first.
  String? _snapshot;

  /// The project is too large to snapshot: only the edits reported are
  /// seen.
  bool _wide = false;

  /// By key ([_key]): path relative to [root], absolute outside it.
  final Map<String, _Entry> _entries = {};

  /// Edits reported since the last look, by key.
  final Map<String, FileChange> _reported = {};

  /// What files the agent reported it edited were before, as it told, for
  /// those the snapshots may not see; by key, null where there was no
  /// file.
  final Map<String, ReviewBlob?> _originals = {};

  /// Edits reported that cannot be undone (what the file was is not
  /// known), by absolute path: listed, to be kept.
  final Map<String, FileChange> _unseen = {};

  List<FileChange> _changes = const [];

  /// The pending changes, one per file, with absolute paths.
  List<FileChange> get changes => _changes;

  /// Why it stopped: a snapshot failed (Git went away). Its changes are
  /// then no longer known.
  String? get failure => _failure;
  String? _failure;

  /// The session it is kept under, once known. Anew, what the one before
  /// kept is kept under it instead.
  String? get session => _session;
  String? _session;
  set session(String? id) {
    if (id == null || id == _session) return;
    final before = _session;
    _session = id;
    unawaited(
      _enqueue(() async {
        // Nothing yet: nothing to keep.
        if (_entries.isEmpty && _unseen.isEmpty) return;
        await _persist();
        if (before != null) await _store.forget(before);
      }),
    );
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

  /// The agent reported an edit to [change]'s file, which was [original]
  /// before; seen at the next [observe].
  void report(FileChange change, {FileOriginal? original}) {
    final path = _key(change.path);
    if (_outside(path) && original == null) {
      // Outside the project, never in a snapshot, and not told what it
      // was.
      _unseen[path] = _merged(_unseen[path], change, path);
      unawaited(_enqueue(_refresh));
      return;
    }
    _reported[path] = change;
    if (original != null &&
        !_entries.containsKey(path) &&
        !_originals.containsKey(path)) {
      unawaited(_enqueue(() => _keepOriginal(path, original)));
    }
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

  /// Keeps what [path] was before the agent's first edit to it, where the
  /// snapshots may not have it: in none of them yet.
  Future<void> _keepOriginal(String path, FileOriginal original) async {
    if (_entries.containsKey(path) || _originals.containsKey(path)) return;
    final snapshot = _snapshot;
    if (snapshot != null &&
        !_outside(path) &&
        await _store.contains(snapshot, path)) {
      return;
    }
    final (known, base) = await _baseOf(path, original);
    if (known) _originals[path] = base;
  }

  /// What [path] was before the agent's edit: whether it is known, and
  /// its blob (null where there was no file).
  Future<(bool, ReviewBlob?)> _baseOf(
    String path,
    FileOriginal original,
  ) async {
    switch (original) {
      case OriginalText(text: null):
        return (true, null);
      case OriginalText(:final text?):
        final now = await _store.current(path);
        final mode = switch (now?.mode) {
          final mode? when mode != '120000' => mode,
          _ => '100644',
        };
        return (true, await _store.store(utf8.encode(text), mode: mode));
      case OriginalByPatch() || OriginalByEdits():
        final after = await _store.take(path);
        if (after == null || after.isLink) return (false, null);
        final now = utf8.decode(await _store.read(after), allowMalformed: true);
        final text = switch (original) {
          OriginalByPatch(:final diff) => unpatch(now, diff),
          OriginalByEdits() => original.undo(now),
          OriginalText() => null,
        };
        if (text == null) return (false, null);
        return (true, await _store.store(utf8.encode(text), mode: after.mode));
    }
  }

  Future<void> _look({required bool agent, List<String>? paths}) async {
    if (paths != null && paths.isEmpty) return;
    final previous = _snapshot;
    // Files outside the project alone: no snapshot to take.
    final inside = paths?.where((path) => !_outside(path)).toList();
    final outsideOnly = inside != null && inside.isEmpty;
    final next = outsideOnly
        ? previous
        : _wide
        ? null
        : await _store.snapshot(paths: inside);
    _snapshot = next;
    if (next == null && !outsideOnly) {
      _wide = true;
      // None of them in a snapshot.
      for (final entry in _entries.values) {
        entry.loose = true;
      }
    }
    var compared = false;
    if (previous != null && next != null) {
      List<ReviewTreeChange>? changes;
      try {
        changes = await _store.diff(previous, next);
      } on Object {
        // The snapshot before was collected since (the checkpoints were
        // cleared, or no look for days).
      }
      if (changes != null) {
        compared = true;
        _compare(changes, agent: agent);
      }
    }
    if (!compared && next != null) {
      // No snapshot to tell from (the first since it was resumed): its
      // files as they are now.
      for (final MapEntry(key: path, value: entry) in _entries.entries) {
        if (entry.loose) continue;
        final now = await _store.current(path);
        if (now == entry.current) continue;
        entry
          ..current = now
          ..conflict = false;
        if (agent) entry.after = now;
      }
    }
    // Those the snapshots leave out, file by file.
    for (final MapEntry(key: path, value: entry) in _entries.entries) {
      if (!entry.loose || (paths != null && !paths.contains(path))) continue;
      final now = await _store.take(path);
      if (now == entry.current) continue;
      entry
        ..current = now
        ..conflict = false;
      if (agent) entry.after = now;
    }
    if (agent) {
      for (final MapEntry(key: path, value: change) in [..._reported.entries]) {
        if (paths != null && !paths.contains(path)) continue;
        _reported.remove(path);
        final known = _originals.containsKey(path);
        final original = _originals.remove(path);
        if (_entries[path] case final entry?) {
          entry
            ..reported = true
            ..shared = false;
        } else if (await _store.exists(path) &&
            (next == null ||
                _outside(path) ||
                !await _store.contains(next, path))) {
          if (known) {
            final now = await _store.take(path);
            _entries[path] = _Entry(original)
              ..after = now
              ..current = now
              ..reported = true
              ..loose = true;
          } else {
            final absolute = _absolute(path);
            _unseen[absolute] = _merged(_unseen[absolute], change, absolute);
          }
        }
      }
      if (paths == null) _overlap = _workingHere.any((r) => r != this);
    }
    // Those it cannot undo that are gone since (a script the agent wrote
    // and deleted): nothing is left of them to keep.
    for (final path in [..._unseen.keys]) {
      if (!await _store.exists(path)) _unseen.remove(path);
    }
    _entries.removeWhere((_, entry) => !entry.pending);
    await _refresh();
    await _persist();
  }

  /// Takes in [changes] from one snapshot to the next: the agent's, or
  /// what is there now.
  void _compare(List<ReviewTreeChange> changes, {required bool agent}) {
    for (final change in changes) {
      // A repository inside the project the snapshots could not look
      // into (those they can are in them, file by file).
      if (change.before?.mode == '160000' || change.after?.mode == '160000') {
        continue;
      }
      var entry = _entries[change.path];
      if (agent) {
        entry ??= _entries[change.path] = _Entry(change.before);
        entry
          ..after = change.after
          ..current = change.after
          ..conflict = false
          ..loose = false;
        _originals.remove(change.path);
        if (_overlap && !entry.reported) entry.shared = true;
      } else if (entry != null) {
        entry
          ..current = change.after
          ..conflict = false
          ..loose = false;
      }
    }
  }

  /// [changes] anew, with their line counts.
  Future<void> _refresh() async {
    final snapshot = _snapshot ?? (_wide ? '' : null);
    final counts = <String, ({int added, int removed})?>{};
    final inside = {
      for (final MapEntry(key: path, value: entry) in _entries.entries)
        if (!_outside(path)) path: entry,
    };
    if (snapshot != null && inside.isNotEmpty) {
      try {
        final now = await _store.overlay(snapshot, {
          for (final MapEntry(key: path, value: entry) in inside.entries)
            if (entry.loose) path: entry.current,
        });
        final base = await _store.overlay(snapshot, {
          for (final MapEntry(key: path, value: entry) in inside.entries)
            path: entry.base,
        });
        counts.addAll(await _store.lineCounts(base, now));
      } on Object {
        // Listed without their counts.
      }
    }
    // Those outside the project, each in a tree of its own.
    for (final MapEntry(key: path, value: entry) in _entries.entries) {
      if (!_outside(path)) continue;
      try {
        final base = await _store.overlay('', {'file': entry.base});
        final now = await _store.overlay('', {'file': entry.current});
        final counted = await _store.lineCounts(base, now);
        if (counted.containsKey('file')) counts[path] = counted['file'];
      } on Object {
        // Listed without its counts.
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
        _entries.remove(_key(path));
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
        final path = _key(absolute);
        final entry = _entries[path];
        if (entry == null) continue;
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

  // --- Part of a file -----------------------------------------------------------

  /// Which text [path] (absolute) is held against: the blob of what was
  /// there before the agent changed it ('' for a file it created), anew as
  /// part of the change is kept; null when it has no change pending that
  /// can be undone.
  String? baseOf(String path) {
    final entry = _entries[_key(path)];
    if (entry == null) return null;
    return entry.base?.oid ?? '';
  }

  /// Keeps part of the change to [path] (absolute): [base], what was there
  /// before with that part of the change in it, is what the rest is held
  /// against. Nothing is written. Fails (the review goes on) where the
  /// store cannot keep it.
  Future<void> keepPart(String path, String base) {
    final key = _key(path);
    final completer = Completer<void>();
    unawaited(
      _enqueue(() async {
        final entry = _entries[key];
        if (entry == null) return completer.complete();
        try {
          final mode = entry.base?.mode ?? entry.current?.mode ?? '100644';
          entry.base = await _store.store(utf8.encode(base), mode: mode);
        } on Object catch (error, stack) {
          return completer.completeError(error, stack);
        }
        entry.conflict = false;
        // The file as it is now (saved since the last look, it may be what
        // is kept): the change goes when nothing of it is left.
        await _look(agent: false, paths: [key]);
        completer.complete();
      }).whenComplete(() {
        if (!completer.isCompleted) completer.complete();
      }),
    );
    return completer.future;
  }

  /// Looks at [paths] (absolute) again after they were written outside the
  /// agent's turn (part of a change undone in the editor): not the agent's.
  Future<void> settle(Iterable<String> paths) {
    final keys = [for (final path in paths) _key(path)];
    return _enqueue(() => _look(agent: false, paths: keys));
  }

  /// The text of [path] (absolute) before the agent changed it: empty for
  /// a file it created; null when it is not known.
  Future<String> Function()? original(String path) {
    final key = _key(path);
    if (!_entries.containsKey(key)) return null;
    return () async {
      final base = _entries[key]?.base;
      if (base == null) return '';
      return utf8.decode(await _store.read(base), allowMalformed: true);
    };
  }

  // --- Keeping it between runs ----------------------------------------------

  Future<void> _persist() async {
    final session = _session;
    if (session == null) return;
    if (_entries.isEmpty && _unseen.isEmpty) {
      await _store.forget(session);
      return;
    }
    await _store.save(
      session,
      jsonEncode({
        'version': 3,
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
      // One of an earlier build (kept with the snapshot it was taken
      // against) is not read: what it listed is begun anew.
      if (json is! Map<String, Object?> || json['version'] != 3) return;
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
      _entries.clear();
      _unseen.clear();
    }
  }

  // --- Paths ------------------------------------------------------------------

  /// [path] (absolute, or relative to [root]) relative to [root], with
  /// `/`; null outside it.
  String? _relative(String path) {
    final absolute = _absolute(path);
    if (!_paths.isWithin(root, absolute)) return null;
    return _paths.split(_paths.relative(absolute, from: root)).join('/');
  }

  /// [path]'s key in the review: relative to [root] ([_relative]), else
  /// absolute (a file outside the project, say in a worktree of its
  /// repository beside it: held file by file, as the agent told what it
  /// was).
  String _key(String path) => _relative(path) ?? _absolute(path);

  /// Whether [key] is of a file outside the project.
  bool _outside(String key) => _paths.isAbsolute(key);

  /// Whether [path] is in the project, spelled either way (see
  /// [ChangeReview.new]'s realRoot).
  bool holds(String path) {
    final absolute = _absolute(path);
    return _paths.equals(root, absolute) || _paths.isWithin(root, absolute);
  }

  String _absolute(String path) {
    final absolute = _paths.normalize(
      _paths.isAbsolute(path)
          ? path
          : _paths.joinAll([root, ...path.split('/')]),
    );
    final real = realRoot;
    if (real == null ||
        !(_paths.equals(real, absolute) || _paths.isWithin(real, absolute))) {
      return absolute;
    }
    return _paths.normalize(
      _paths.join(root, _paths.relative(absolute, from: real)),
    );
  }

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
