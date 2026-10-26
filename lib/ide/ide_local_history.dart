// JetBrains IDEs' Local History, as far as saves go: each file's text as
// it was saved, kept a week (the last versions of a file at most) apart
// from Git, to be looked at against the file and taken back from.

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'ide_local_history_stub.dart'
    if (dart.library.io) 'ide_local_history_io.dart'
    as platform;

/// A version of a file kept: [time] it was saved (or seen before a save).
class IdeLocalVersion {
  const IdeLocalVersion(this.path, this.id, this.time);

  final String path;
  final String id;
  final DateTime time;
}

/// Where the versions are kept: a folder for each file, by [key].
abstract interface class IdeLocalHistoryStore {
  /// The ids of [key]'s versions, as written.
  Future<List<String>> list(String key);
  Future<String> read(String key, String id);
  Future<void> write(String key, String id, String text);
  Future<void> remove(String key, String id);
}

class IdeLocalHistory {
  IdeLocalHistory(
    this._store, {
    this.versions = 50,
    this.age = const Duration(days: 7),
    this.largest = 1 << 20,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Kept in the app's data folder; none where there is no file system.
  static IdeLocalHistory? inDataDirectory() => switch (platform.dataStore()) {
    final store? => IdeLocalHistory(store),
    null => null,
  };

  final IdeLocalHistoryStore _store;
  final DateTime Function() _now;

  /// How many of a file's versions are kept, and how long; and the largest
  /// text kept.
  final int versions;
  final Duration age;
  final int largest;

  /// The text last kept of each file, so as not to keep it again.
  final Map<String, String> _last = {};

  Future<void> _queue = Future.value();

  static String _key(String path) =>
      sha1.convert(utf8.encode(path)).toString().substring(0, 20);

  /// Keeps [text] as [path]'s latest version, unless it is that already.
  Future<void> record(String path, String text) =>
      _queue = _queue.then((_) => _record(path, text)).catchError((Object _) {
        // History is a help: a write that fails loses a version, no more.
      });

  Future<void> _record(String path, String text) async {
    if (text.length > largest) return;
    final key = _key(path);
    final ids = [...await _store.list(key)]..sort();
    final last =
        _last[path] ?? (ids.isEmpty ? null : await _store.read(key, ids.last));
    _last[path] = text;
    if (last == text) return;
    var id = '${_now().millisecondsSinceEpoch}';
    // Two in a millisecond: the later after.
    while (ids.contains(id)) {
      id = '${int.parse(id) + 1}';
    }
    await _store.write(key, id, text);
    ids.add(id);
    final oldest = _now().subtract(age).millisecondsSinceEpoch;
    for (final (index, old) in ids.indexed) {
      if (index < ids.length - versions || int.parse(old) < oldest) {
        await _store.remove(key, old);
      }
    }
  }

  /// [path]'s versions, the latest first.
  Future<List<IdeLocalVersion>> versionsOf(String path) async {
    await _queue;
    final ids = await _store.list(_key(path));
    return [
      for (final id in ids)
        if (int.tryParse(id) case final millis?)
          IdeLocalVersion(
            path,
            id,
            DateTime.fromMillisecondsSinceEpoch(millis),
          ),
    ]..sort((a, b) => b.time.compareTo(a.time));
  }

  Future<String> read(IdeLocalVersion version) =>
      _store.read(_key(version.path), version.id);
}

/// Versions in memory (tests).
class IdeMemoryLocalHistoryStore implements IdeLocalHistoryStore {
  final Map<String, Map<String, String>> files = {};

  @override
  Future<List<String>> list(String key) async => [...?files[key]?.keys];

  @override
  Future<String> read(String key, String id) async => files[key]![id]!;

  @override
  Future<void> write(String key, String id, String text) async =>
      (files[key] ??= {})[id] = text;

  @override
  Future<void> remove(String key, String id) async => files[key]?.remove(id);
}
