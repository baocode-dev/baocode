import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'stash_disk.dart';
import 'stash_note.dart';
import 'stash_settings.dart';

/// Files up to this size are copied into a stash's folder; a bigger one is
/// only linked to, unless the user asks for it to be copied.
const stashCopyLimit = 200 * 1024 * 1024;

/// The stashes, as their files are: read once, written as they change,
/// read again when another app writes one (see docs/stash.md).
class StashStore extends ChangeNotifier {
  StashStore(this.disk, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// The app's, once main() has made it.
  static StashStore? current;

  final StashDisk disk;
  final DateTime Function() _clock;

  final Map<int, StashNote> _notes = {};

  /// Where merged stashes' numbers lead (see [merge]).
  final Map<int, int> _redirects = {};

  /// The issues not to be stashes again: those whose stash was deleted, or
  /// unlinked from it (in `.stash.json`, as the user's answer).
  Set<String> get ignoredIssues => Set.unmodifiable(_ignored);
  final Set<String> _ignored = {};

  /// Keeps [url]'s issue from being a stash again (see [ignoredIssues]).
  Future<void> ignoreIssue(String url) async {
    if (!_ignored.add(url)) return;
    await disk.locked(() async {
      final meta = await disk.readMeta();
      meta['ignoredIssues'] = {
        ...?(meta['ignoredIssues'] as List?)?.whereType<String>(),
        url,
      }.toList();
      await disk.writeMeta(meta);
    });
  }

  /// [url]'s issue may be a stash again (imported by the user).
  Future<void> unignoreIssue(String url) async {
    if (!_ignored.remove(url)) return;
    await disk.locked(() async {
      final meta = await disk.readMeta();
      meta['ignoredIssues'] = [
        ...?(meta['ignoredIssues'] as List?)?.whereType<String>(),
      ]..remove(url);
      await disk.writeMeta(meta);
    });
  }

  bool _loaded = false;
  bool get loaded => _loaded;
  Future<void>? _loading;
  StreamSubscription<void>? _watching;

  /// All of them, newest first.
  List<StashNote> get notes => _sorted ??= List.unmodifiable(
    _notes.values.toList()..sort((a, b) => b.created.compareTo(a.created)),
  );

  /// [notes], kept until they change: the sidebar asks for them for each
  /// of its rows, each build.
  List<StashNote>? _sorted;

  @override
  void notifyListeners() {
    _sorted = null;
    super.notifyListeners();
  }

  /// [id]'s stash, following a merged one's number to the one it went
  /// into; null when there is none.
  StashNote? byId(int id) {
    var at = id;
    for (var hops = 0; hops < 16; hops++) {
      if (_notes[at] case final note?) return note;
      final next = _redirects[at];
      if (next == null) return null;
      at = next;
    }
    return null;
  }

  /// The order they were dragged in (see [reorder]): their numbers, the
  /// first at the top.
  List<int> get order => List.unmodifiable(_order);
  List<int> _order = const [];

  /// Keeps [ids] as the order they were dragged in, for every window and
  /// app (in `.stash.json`).
  Future<void> reorder(List<int> ids) async {
    _order = [...ids];
    notifyListeners();
    await disk.locked(() async {
      final meta = await disk.readMeta();
      meta['order'] = [..._order.where(_notes.containsKey)];
      await disk.writeMeta(meta);
    });
  }

  /// [notes] in [sort]'s order; those pinned first, but in the order
  /// dragged. Of those never dragged, the newest first, at the top.
  List<StashNote> sorted(Iterable<StashNote> notes, StashSort sort) {
    final list = [...notes];
    final rank = {for (final (i, id) in _order.indexed) id: i};
    int compare(StashNote a, StashNote b) => switch (sort) {
      StashSort.updated => b.updated.compareTo(a.updated),
      StashSort.created => b.created.compareTo(a.created),
      StashSort.number => b.id.compareTo(a.id),
      StashSort.manual => switch ((rank[a.id], rank[b.id])) {
        (final x?, final y?) => x.compareTo(y),
        (null, _?) => -1,
        (_?, null) => 1,
        _ => b.created.compareTo(a.created),
      },
    };
    list.sort((a, b) {
      if (sort != StashSort.manual && a.pinned != b.pinned) {
        return a.pinned ? -1 : 1;
      }
      final by = compare(a, b);
      return by != 0 ? by : b.id.compareTo(a.id);
    });
    return list;
  }

  /// The stash folder (absolute).
  String get root => disk.root;

  /// [path] as a stash's text gives it, absolute.
  String absolute(String path) => stashAbsolute(disk.root, path);

  /// [id]'s stash's file (`<root>/12.md`), if it is kept; where it opens as
  /// the Stash page shows it (see `stashFileView`).
  String? fileOf(int id) =>
      root.isEmpty || _notes[id] == null ? null : p.join(root, '$id.md');

  /// The stash whose file [path] is (`<root>/12.md`), if one is.
  int? idOfFile(String path) {
    if (root.isEmpty || !p.equals(p.dirname(path), root)) return null;
    final id = switch (RegExp(r'^(\d+)\.md$').firstMatch(p.basename(path))) {
      final match? => int.parse(match[1]!),
      null => null,
    };
    return id == null ? null : _notes[id]?.id;
  }

  /// Reads the folder (once; again for [reload]), and follows other apps'
  /// changes to it.
  Future<void> load() => _loading ??= _read();

  Future<void> reload() => _read();

  Future<void> _read() async {
    final listed = await disk.list();
    final meta = await disk.readMeta();
    _redirects
      ..clear()
      ..addAll(_parseRedirects(meta['redirects']));
    _ignored
      ..clear()
      ..addAll([
        if (meta['ignoredIssues'] case final List<Object?> urls)
          ...urls.whereType<String>(),
      ]);
    final order = _parseOrder(meta['order']);
    final reordered = !listEquals(order, _order);
    _order = order;
    final read = <int, StashNote>{};
    for (final MapEntry(key: id, value: modified) in listed.entries) {
      final known = _notes[id];
      // Unchanged since it was read (or written here: its file's time comes
      // a little after): kept as it is.
      final seen = _writtenAt[id] ?? _readAt[id];
      if (known != null &&
          seen != null &&
          !modified.isAfter(seen.add(_slack))) {
        read[id] = known;
        continue;
      }
      final text = await disk.read(id);
      if (text == null) continue;
      read[id] = StashNote.decode(id, text, modified: modified);
      _readAt[id] = modified;
    }
    final changed =
        !_loaded ||
        reordered ||
        read.length != _notes.length ||
        read.entries.any((entry) => !identical(_notes[entry.key], entry.value));
    _notes
      ..clear()
      ..addAll(read);
    _sorted = null;
    _loaded = true;
    _watching ??= disk.changes.listen((_) => unawaited(reload()));
    if (changed) notifyListeners();
  }

  static List<int> _parseOrder(Object? json) => [
    if (json is List)
      for (final id in json)
        if (id is int) id,
  ];

  static Map<int, int> _parseRedirects(Object? json) => {
    if (json is Map)
      for (final MapEntry(:key, :value) in json.entries)
        if (int.tryParse('$key') case final from? when value is int)
          from: value,
  };

  /// When each stash was last written here, and its file's time when it
  /// was last read.
  final Map<int, DateTime> _writtenAt = {};
  final Map<int, DateTime> _readAt = {};

  /// How long after a write here its file's time may be.
  static const _slack = Duration(seconds: 2);

  /// A new number: one past the highest ever given, never one used before.
  Future<int> _allocate() => disk.locked(() async {
    final meta = await disk.readMeta();
    final listed = await disk.list();
    var next = switch (meta['next']) {
      final int next => next,
      _ => 1,
    };
    for (final id in [...listed.keys, ..._notes.keys, ..._redirects.keys]) {
      if (id >= next) next = id + 1;
    }
    meta['next'] = next + 1;
    await disk.writeMeta(meta);
    return next;
  });

  /// A new stash with [body], from [source], about [project] if it is
  /// known; written at once.
  Future<StashNote> create({
    String body = '',
    StashSource source = StashSource.none,
    String? project,
  }) async {
    await load();
    final id = await _allocate();
    final note = StashNote(
      id: id,
      created: _clock(),
      body: body,
      source: source,
      project: project,
    );
    _notes[id] = note;
    _sorted = null;
    await _write(note);
    notifyListeners();
    return note;
  }

  /// Writes [note] (changed in place) and tells the listeners; [touch]
  /// marks it updated now.
  Future<void> save(StashNote note, {bool touch = true}) async {
    if (touch) note.updated = _clock();
    _notes[note.id] = note;
    notifyListeners();
    await _write(note);
  }

  /// Changes [id]'s stash with [change] and writes it; nothing for none.
  Future<StashNote?> update(
    int id,
    void Function(StashNote note) change, {
    bool touch = true,
  }) async {
    final note = byId(id);
    if (note == null) return null;
    change(note);
    await save(note, touch: touch);
    return note;
  }

  Future<void> _write(StashNote note) async {
    // The file's time, not the notes' clock.
    _writtenAt[note.id] = DateTime.now();
    await disk.write(note.id, note.encode());
  }

  /// Deletes [id]'s stash, its pictures and files with it. Its number is
  /// never given again; the issue it was, never a stash again.
  Future<void> delete(int id) async {
    final note = _notes.remove(id);
    if (note == null) return;
    _sorted = null;
    notifyListeners();
    await disk.delete(id);
    if (note.ownIssue case final url?) await ignoreIssue(url);
  }

  /// The stash a stash that is blank was opened for, and closed without
  /// anything written: it goes, as if never made.
  Future<void> discardIfBlank(int id) async {
    final note = _notes[id];
    if (note == null || !note.isBlank) return;
    await delete(id);
    // Its number is the next one's again, if none was given after it.
    await disk.locked(() async {
      final meta = await disk.readMeta();
      if (meta['next'] != id + 1) return;
      final listed = await disk.list();
      final taken = [...listed.keys, ..._notes.keys, ..._redirects.keys];
      if (taken.any((other) => other >= id)) return;
      meta['next'] = id;
      await disk.writeMeta(meta);
    });
  }

  // --- Pictures and files ------------------------------------------------------

  /// Keeps [bytes], a picture pasted or dropped, in [id]'s folder; the
  /// path its text gives it.
  Future<String> addImage(int id, Uint8List bytes, {String? name}) =>
      disk.writeAsset(
        id,
        name ?? 'image-${_clock().millisecondsSinceEpoch}.png',
        bytes,
      );

  /// Puts the file at [path] into [id]'s stash: copied into its folder up
  /// to [stashCopyLimit] (or with [copyAnyway]), else linked to where it
  /// is. Null when there is no file there.
  Future<StashFileAdded?> addFile(
    int id,
    String path, {
    bool copyAnyway = false,
  }) async {
    final size = await disk.sizeOf(path);
    if (size == null) return null;
    if (size > stashCopyLimit && !copyAnyway) {
      return (path: path, copied: false, size: size);
    }
    return (path: await disk.copyAsset(id, path), copied: true, size: size);
  }

  // --- Merging -----------------------------------------------------------------

  /// Puts [ids]' stashes into one: the lowest number's, their texts one
  /// after another, oldest first. The others go, their numbers leading to
  /// it from then on (`#5` in a text finds it); their pictures and files
  /// move into its folder.
  Future<StashNote?> merge(List<int> ids) async {
    final merging = [for (final id in ids.toSet()) ?byId(id)]
      ..sort((a, b) => a.created.compareTo(b.created));
    if (merging.length < 2) return merging.firstOrNull;
    final kept = merging.reduce((a, b) => a.id < b.id ? a : b);
    final parts = <String>[];
    for (final note in merging) {
      var body = note.body.trim();
      if (!identical(note, kept)) {
        final moved = await disk.moveAssets(note.id, kept.id);
        body = rewriteAssetPaths(body, moved);
      }
      if (body.isNotEmpty) parts.add(body);
    }
    // Their issues and conversations kept with it: an issue that was one
    // of them, a stash again, would be its double.
    for (final note in merging) {
      if (identical(note, kept)) continue;
      final own = note.ownIssue;
      for (final link in note.issues) {
        if (kept.issueOf(link.url) != null) continue;
        // Its issue the same thing as this one's: closed as its duplicate?
        kept.issues.add(
          link.url == own ? link.copyWith(mergedFrom: note.id) : link,
        );
      }
      for (final link in note.threads) {
        if (kept.threadOf(link.session) == null) kept.threads.add(link);
      }
      // None of its own: theirs, its text changed since (to be pushed).
      if (kept.ownIssue == null && !kept.local && note.ownIssue != null) {
        kept
          ..issue = note.ownIssue
          ..synced = note.synced
          ..syncedRemote = note.syncedRemote;
      }
    }
    kept
      ..body = parts.join('\n\n---\n\n')
      ..pinned = merging.any((note) => note.pinned)
      ..project =
          kept.project ??
          merging.map((note) => note.project).nonNulls.firstOrNull;
    if (kept.title.isNotEmpty &&
        merging.any((n) => !identical(n, kept) && n.title.isNotEmpty)) {
      // The titles were each one's.
      kept.title = '';
    }
    final gone = [
      for (final note in merging)
        if (!identical(note, kept)) note.id,
    ];
    await disk.locked(() async {
      final meta = await disk.readMeta();
      final redirects = {
        ...?(meta['redirects'] as Map?)?.cast<String, Object?>(),
        for (final id in gone) '$id': kept.id,
      };
      meta['redirects'] = redirects;
      await disk.writeMeta(meta);
    });
    for (final id in gone) {
      _redirects[id] = kept.id;
      _notes.remove(id);
      _sorted = null;
      await disk.delete(id);
    }
    await save(kept);
    return kept;
  }

  // --- Search ----------------------------------------------------------------

  /// Text read out of the pictures (see StashController), by their
  /// absolute paths.
  final Map<String, String> pictureText = {};

  /// [text] read out of the picture at [path]: told to the listeners when
  /// there is some, a stash of pictures alone being called by it.
  void pictureRead(String path, String text) {
    pictureText[path] = text;
    if (text.trim().isNotEmpty) notifyListeners();
  }

  /// What a stash is called: its title or first line (see
  /// [StashNote.displayTitle]); with no text, the first line read out of
  /// its pictures. Empty when there is neither.
  String headline(StashNote note) {
    final title = note.displayTitle;
    if (title.isNotEmpty) return title;
    for (final image in note.images) {
      final text = pictureText[absolute(image)];
      if (text == null) continue;
      for (final line in text.split('\n')) {
        if (line.trim().isNotEmpty) return line.trim();
      }
    }
    return '';
  }

  /// The stashes whose words have all of [query]'s (in their title, text,
  /// source, or the text of their pictures), the best first: an empty
  /// query, all of them.
  List<StashNote> search(String query, {Iterable<StashNote>? among}) {
    final words = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    final notes = among?.toList() ?? this.notes;
    if (words.isEmpty) return notes;
    final scored = <(StashNote, int)>[];
    for (final note in notes) {
      final title = note.displayTitle.toLowerCase();
      final haystack = searchText(note).toLowerCase();
      var score = 0;
      var all = true;
      for (final word in words) {
        if (word == note.tag || word == '${note.id}') {
          score += 100;
          continue;
        }
        if (!haystack.contains(word)) {
          all = false;
          break;
        }
        if (title.contains(word)) score += 10;
        score += word.allMatches(haystack).length;
      }
      if (all) scored.add((note, score));
    }
    scored.sort((a, b) {
      final by = b.$2.compareTo(a.$2);
      return by != 0 ? by : b.$1.created.compareTo(a.$1.created);
    });
    return [for (final (note, _) in scored) note];
  }

  /// All a stash says, as search reads it.
  String searchText(StashNote note) => [
    note.tag,
    note.title,
    plainText(note.body),
    if (note.project case final project?) p.basename(project),
    for (final image in note.images) ?pictureText[absolute(image)],
  ].join('\n');

  @override
  void dispose() {
    unawaited(_watching?.cancel());
    super.dispose();
  }
}

/// [text] with the paths in [moved] (old to new) replaced.
String rewriteAssetPaths(String text, Map<String, String> moved) {
  var result = text;
  for (final MapEntry(key: from, value: to) in moved.entries) {
    result = result.replaceAll(
      RegExp('(?<![\\w/])${RegExp.escape(from)}(?![\\w.])'),
      to,
    );
  }
  return result;
}
