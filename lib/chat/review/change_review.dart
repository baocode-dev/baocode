import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../remote/remote_location.dart';
import '../chat_models.dart';
import 'review_store.dart';
import 'unpatch.dart';

/// A file the agent changed: what it was before, and what the agent left.
class _Entry {
  _Entry(this.base) : after = base, current = base;

  /// What it was before the agent's first edit, with what changed in it
  /// since that was not the agent's: undone, the file goes back to it.
  ReviewBlob? base;

  /// What the agent left: its change is from [base] to this.
  ReviewBlob? after;

  /// What is there now, as last looked at (not kept).
  ReviewBlob? current;

  /// Undo could not carry over what changed since the agent left it.
  bool conflict = false;

  /// Edits of it begun and not done: the agent may be writing it.
  int writing = 0;

  /// Whether the agent changed it, and it is not back as it was.
  bool get pending => !_same(base, after) && !_same(base, current);

  Map<String, Object?> toJson() => {
    'base': base?.toJson(),
    'after': after?.toJson(),
    'conflict': conflict,
  };

  static _Entry fromJson(Map<String, Object?> json) {
    final after = ReviewBlob.fromJson(json['after']);
    return _Entry(ReviewBlob.fromJson(json['base']))
      ..after = after
      ..current = after
      ..conflict = json['conflict'] == true;
  }
}

bool _same(ReviewBlob? a, ReviewBlob? b) =>
    a == null ? b == null : a.sameContent(b);

/// What an agent changed, held against what was there before, for the
/// user to keep or undo file by file: the review behind Keep and Undo.
///
/// The kernel tells it of each edit as the agent makes it: [before], it
/// keeps what the file is (the agent writes once that is done), and
/// [after], what the agent left. One that tells of an edit only once it is
/// made ([report]) tells what the file was ([FileOriginal]). What a
/// command writes is not seen.
///
/// Its account is of its own agent's edits alone: what else changes a
/// file it changed (another agent, the user) is not its, and is put into
/// what it holds the file against when the agent edits it again. Undo
/// takes the agent's change out of the file as it is (a three-way merge):
/// where it cannot, the file is left as it is and marked.
///
/// Kept, a change is only no longer listed: nothing is written, staged or
/// committed. Undone, the file is put back.
class ChangeReview extends ChangeNotifier {
  /// Its files' paths spelled as [paths] has them: this machine's way
  /// when null.
  ///
  /// [realRoot] is [root] with its links resolved, where that is another
  /// path: the agent may tell the project's files by it (Claude Code does:
  /// macOS's `/tmp` is `/private/tmp`), and they are listed by [root].
  ChangeReview(
    this._store, {
    required this.root,
    p.Context? paths,
    this.realRoot,
  }) : _paths = paths ?? p.context;

  /// The review of the agent working in [root], continuing what [session]
  /// left; null where there can be none (see [openReviewStore]).
  static Future<ChangeReview?> open(String root, {String? session}) async {
    final store = await openReviewStore(root);
    if (store == null) return null;
    // A remote project's paths are its host's (POSIX), whatever this
    // machine spells its own with.
    final paths = RemoteLocation.pathsOf(root);
    final realRoot = await realRootOf(root);
    root = RemoteLocation.pathOf(root);
    if (session == null) {
      return ChangeReview(store, root: root, paths: paths, realRoot: realRoot);
    }
    return resume(store, session, root: root, paths: paths, realRoot: realRoot);
  }

  /// The review over [store], with the changes [session] left pending.
  static Future<ChangeReview> resume(
    ReviewStore store,
    String session, {
    required String root,
    p.Context? paths,
    String? realRoot,
  }) async {
    final review = ChangeReview(
      store,
      root: root,
      paths: paths,
      realRoot: realRoot,
    );
    await review._load(session);
    return review;
  }

  final ReviewStore _store;
  final p.Context _paths;

  /// The agent's directory (on its host): a path it tells relative is in
  /// it.
  final String root;

  /// [root] with its links resolved, where that is another path.
  final String? realRoot;

  /// How its files' paths are spelled.
  p.Context get paths => _paths;

  /// By absolute path.
  final Map<String, _Entry> _entries = {};

  /// Edits it was told of that cannot be undone (what the file was is not
  /// known), by absolute path: listed, to be kept.
  final Map<String, FileChange> _unseen = {};

  List<FileChange> _changes = const [];

  /// The pending changes, one per file, with absolute paths.
  List<FileChange> get changes => _changes;

  /// Why it stopped: the store failed (the remote host went away). Its
  /// changes are then no longer known.
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

  // --- The agent's edits --------------------------------------------------------

  /// The agent is about to write [path]: what is there is kept, the first
  /// time, as what it was; and what changed in it since the agent last
  /// wrote it is not the agent's.
  Future<void> before(String path) {
    final key = _key(path);
    return _enqueue(() async {
      final entry = _entries[key];
      if (entry == null) {
        try {
          _entries[key] = _Entry(await _store.take(key))..writing = 1;
        } on Exception {
          // Not to be kept (too large): listed once reported, not undone.
        }
        return;
      }
      // Another edit of the agent's under way: what changed may be its.
      final busy = entry.writing > 0;
      entry.writing++;
      if (busy) return;
      final now = await _store.current(key);
      entry.current = now;
      if (!_same(now, entry.after)) await _rebase(entry, key);
    });
  }

  /// What changed in [entry]'s file since the agent left it (another
  /// agent, the user) put into what it is held against: the agent's change
  /// stays its own.
  Future<void> _rebase(_Entry entry, String key) async {
    final now = await _store.take(key);
    final base = entry.base;
    final after = entry.after;
    if (now == null || after == null) {
      // Deleted since, or there again since the agent deleted it: what
      // the agent did to it is gone.
      entry.base = now;
    } else if (base != null && !base.isLink && !after.isLink && !now.isLink) {
      final merged = await _store.merge(base, after, now);
      // Where it cannot be told apart, it is the agent's.
      if (merged != null) {
        entry.base = await _store.store(merged, mode: now.mode);
      }
    }
    entry
      ..after = now
      ..current = now
      ..conflict = false;
  }

  /// The agent wrote [path], or gave up writing it: what it left is its
  /// change.
  Future<void> after(String path) {
    final key = _key(path);
    return _enqueue(() async {
      final entry = _entries[key];
      if (entry == null) return;
      if (entry.writing > 0) entry.writing--;
      await _taken(entry, key);
      await _refresh();
      await _persist();
    });
  }

  /// [entry]'s file as it is now is what the agent left.
  Future<void> _taken(_Entry entry, String key) async {
    final now = await _store.take(key);
    entry
      ..after = now
      ..current = now
      ..conflict = false;
  }

  /// The agent edited [change]'s file, which was [original] before: told
  /// once the edit is made, by a kernel that does not tell [before] (or
  /// tells this as well).
  void report(FileChange change, {FileOriginal? original}) {
    final key = _key(change.path);
    unawaited(
      _enqueue(() async {
        if (_entries[key] case final entry?) {
          // Its last edit done: what it left, once more.
          if (entry.writing == 0) await _taken(entry, key);
        } else {
          await _adopt(key, change, original);
        }
        await _refresh();
        await _persist();
      }),
    );
  }

  /// [key]'s file, edited without [before]: held against what it was as
  /// the agent told, else listed to be kept.
  Future<void> _adopt(
    String key,
    FileChange change,
    FileOriginal? original,
  ) async {
    final known = original == null ? null : await _baseOf(key, original);
    if (known == null) {
      _unseen[key] = FileChange(
        path: key,
        added: (_unseen[key]?.added ?? 0) + change.added,
        removed: (_unseen[key]?.removed ?? 0) + change.removed,
        tracked: false,
      );
      return;
    }
    final now = await _store.take(key);
    _entries[key] = _Entry(known.base)
      ..after = now
      ..current = now;
  }

  /// What [path] was before the agent's edit, as [original] tells; null
  /// where that is not known.
  Future<({ReviewBlob? base})?> _baseOf(
    String path,
    FileOriginal original,
  ) async {
    switch (original) {
      case OriginalText(text: null):
        return (base: null);
      case OriginalText(:final text?):
        final now = await _store.current(path);
        final mode = switch (now?.mode) {
          final mode? when mode != '120000' => mode,
          _ => '100644',
        };
        return (base: await _store.store(utf8.encode(text), mode: mode));
      case OriginalByPatch() || OriginalByEdits():
        final after = await _store.take(path);
        if (after == null || after.isLink) return null;
        final now = utf8.decode(await _store.read(after), allowMalformed: true);
        final text = switch (original) {
          OriginalByPatch(:final diff) => unpatch(now, diff),
          OriginalByEdits() => original.undo(now),
          OriginalText() => null,
        };
        if (text == null) return null;
        return (base: await _store.store(utf8.encode(text), mode: after.mode));
    }
  }

  /// Looks at its files again, as a turn ends: what changed since is not
  /// the agent's, and edits it began and did not tell the end of (denied,
  /// stopped) are over.
  Future<void> look() => _enqueue(() async {
    for (final MapEntry(key: path, value: entry) in _entries.entries) {
      if (entry.writing > 0) {
        entry.writing = 0;
        await _taken(entry, path);
        continue;
      }
      final now = await _store.current(path);
      if (_same(now, entry.current)) continue;
      entry
        ..current = now
        ..conflict = false;
    }
    // Those it cannot undo that are gone since (a script the agent wrote
    // and deleted): nothing is left of them to keep.
    for (final path in [..._unseen.keys]) {
      if (await _store.current(path) == null) _unseen.remove(path);
    }
    await _refresh();
    await _persist();
  });

  /// Line counts worked out not long ago, by the blobs counted between:
  /// named by what is in them, they count the same again.
  static final Map<String, ({int added, int removed})?> _counts = {};

  Future<({int added, int removed})?> _countsOf(_Entry entry) async {
    final key = '${entry.base?.oid}>${entry.after?.oid}';
    if (_counts.containsKey(key)) return _counts[key] = _counts.remove(key);
    final counts = await _store.lineCounts(entry.base, entry.after);
    _counts[key] = counts;
    if (_counts.length > 256) _counts.remove(_counts.keys.first);
    return counts;
  }

  /// [changes] anew, with their line counts.
  Future<void> _refresh() async {
    _entries.removeWhere((_, entry) => !entry.pending && entry.writing == 0);
    final listed = <FileChange>[];
    for (final path in _entries.keys.toList()..sort()) {
      final entry = _entries[path]!;
      if (!entry.pending) continue;
      ({int added, int removed})? counts;
      var counted = false;
      try {
        counts = await _countsOf(entry);
        counted = true;
      } on Exception {
        // Listed without its counts.
      }
      listed.add(
        FileChange(
          path: path,
          added: counts?.added ?? 0,
          removed: counts?.removed ?? 0,
          binary: counted && counts == null,
          kind: entry.base == null
              ? FileChangeKind.added
              : entry.after == null
              ? FileChangeKind.deleted
              : FileChangeKind.modified,
          conflict: entry.conflict,
        ),
      );
    }
    _changes = [...listed, ..._unseen.values];
    if (!_disposed) notifyListeners();
  }

  // --- Keep and Undo -----------------------------------------------------------

  /// Keeps the changes to [paths] (absolute): they are no longer listed.
  Future<void> keep(Iterable<String> paths) {
    final kept = [for (final path in paths) _key(path)];
    return _enqueue(() async {
      for (final path in kept) {
        _unseen.remove(path);
        _entries.remove(path);
      }
      await _refresh();
      await _persist();
    });
  }

  Future<void> keepAll() => _enqueue(() async {
    _unseen.clear();
    _entries.removeWhere((_, entry) => entry.writing == 0);
    await _refresh();
    await _persist();
  });

  /// Puts the files at [paths] (absolute) back as they were before the
  /// agent changed them, keeping what changed since where it can (else the
  /// file stays, marked [FileChange.conflict]).
  Future<void> undo(Iterable<String> paths) {
    final wanted = [for (final path in paths) _key(path)];
    return _enqueue(() async {
      for (final path in wanted) {
        final entry = _entries[path];
        if (entry == null || !entry.pending) continue;
        try {
          if (await _undo(path, entry)) {
            _entries.remove(path);
          } else {
            entry.conflict = true;
          }
        } on Exception {
          entry.conflict = true;
        }
      }
      await _refresh();
      await _persist();
    });
  }

  Future<void> undoAll() => undo([
    for (final MapEntry(key: path, value: entry) in _entries.entries)
      if (entry.pending) path,
  ]);

  /// Whether [path] is back as it was.
  Future<bool> _undo(String path, _Entry entry) async {
    final now = await _store.current(path);
    final base = entry.base;
    final after = entry.after;
    // Already back.
    if (_same(base, now)) return true;
    // As the agent left it: put back what was.
    if (_same(now, after)) {
      await _store.restore(path, base, root: root);
      return true;
    }
    // Changed since: the agent's change taken out of it.
    if (now != null && after != null && base != null && !now.isLink) {
      final mine = await _store.take(path);
      if (mine == null) return false;
      final merged = await _store.merge(mine, after, base);
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
    if (entry == null || !entry.pending) return null;
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
          final mode = entry.base?.mode ?? entry.after?.mode ?? '100644';
          entry.base = await _store.store(utf8.encode(base), mode: mode);
          // The file as it is now (saved since, it may be what is kept):
          // the change goes when nothing of it is left.
          entry
            ..current = await _store.current(key)
            ..conflict = false;
        } on Object catch (error, stack) {
          return completer.completeError(error, stack);
        }
        await _refresh();
        await _persist();
        completer.complete();
      }).whenComplete(() {
        if (!completer.isCompleted) completer.complete();
      }),
    );
    return completer.future;
  }

  /// Looks at [paths] (absolute) again after they were written outside the
  /// agent's turn (part of a change undone in the editor): what is left of
  /// the agent's change is what is there.
  Future<void> settle(Iterable<String> paths) {
    final keys = [for (final path in paths) _key(path)];
    return _enqueue(() async {
      for (final key in keys) {
        if (_entries[key] case final entry?) await _taken(entry, key);
      }
      await _refresh();
      await _persist();
    });
  }

  /// The text of [path] (absolute) before the agent changed it: empty for
  /// a file it created; null when it is not known.
  Future<String> Function()? original(String path) {
    final key = _key(path);
    if (_entries[key]?.pending != true) return null;
    return () async {
      final base = _entries[key]?.base;
      if (base == null) return '';
      return utf8.decode(await _store.read(base), allowMalformed: true);
    };
  }

  // --- Keeping it between runs ----------------------------------------------

  /// The session and what [_persist] last kept under it (empty: nothing):
  /// kept again only once it changed.
  String? _persisted;

  Future<void> _persist() async {
    final session = _session;
    if (session == null) return;
    final kept = {
      for (final MapEntry(key: path, value: entry) in _entries.entries)
        if (entry.pending) path: entry,
    };
    final nothing = kept.isEmpty && _unseen.isEmpty;
    final data = nothing
        ? ''
        : jsonEncode({
            'version': 4,
            'entries': {
              for (final MapEntry(key: path, value: entry) in kept.entries)
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
          });
    final record = '$session\x00$data';
    if (record == _persisted) return;
    if (nothing) {
      await _store.forget(session);
    } else {
      await _store.save(
        session,
        data,
        blobs: [
          for (final entry in kept.values) ...[?entry.base, ?entry.after],
        ],
      );
    }
    _persisted = record;
  }

  Future<void> _load(String session) async {
    _session = session;
    try {
      final data = await _store.load(session);
      if (data == null) return;
      final json = jsonDecode(data);
      if (json is! Map<String, Object?> || json['version'] != 4) return;
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
      _persisted = '$session\x00$data';
      await _refresh();
    } on Object {
      // Begun anew.
      _entries.clear();
      _unseen.clear();
    }
  }

  // --- Paths ------------------------------------------------------------------

  /// [path] (absolute, or relative to [root]) absolute, normalized, and in
  /// [root] where it is in [realRoot].
  String _key(String path) {
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
    _persisted = null;
    if (session == null) return Future.value();
    return _queue = _queue.then(
      (_) => _store.forget(session).catchError((Object _) {}),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
