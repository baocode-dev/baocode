import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:path/path.dart' as p;

/// What happened to a path under a watched folder.
enum WatchChange { created, modified, deleted }

/// A change under a watched folder.
class WatchEvent {
  const WatchEvent(this.path, this.change);

  final String path;
  final WatchChange change;

  @override
  String toString() => 'WatchEvent($path, ${change.name})';
}

/// The changes to everything under [root], skipping the folders [skip]
/// says to (their paths, absolute).
///
/// macOS and Windows watch a tree natively; Linux's inotify watches one
/// folder at a time, so there each folder is watched on its own, and new
/// ones as they appear. Past the system's limit on watches
/// (`fs.inotify.max_user_watches`) the folders left over are not watched:
/// [onLimit] is told once, and the rest goes on.
Stream<WatchEvent> watchRecursively(
  String root, {
  bool Function(String directory)? skip,
  void Function(String message)? onLimit,
  bool? perDirectory,
}) {
  if (!FileSystemEntity.isWatchSupported) return const Stream.empty();
  if (!(perDirectory ?? Platform.isLinux)) {
    try {
      return Directory(root)
          .watch(recursive: true)
          .expand(_events)
          .where((event) => !_skipped(root, event.path, skip))
          .handleError((Object _) {});
    } on Object {
      return const Stream.empty();
    }
  }
  return _TreeWatcher(root, skip, onLimit).stream;
}

bool _skipped(String root, String path, bool Function(String)? skip) {
  if (skip == null) return false;
  var dir = p.dirname(path);
  while (p.isWithin(root, dir)) {
    if (skip(dir)) return true;
    dir = p.dirname(dir);
  }
  return false;
}

Iterable<WatchEvent> _events(FileSystemEvent event) => switch (event) {
  FileSystemCreateEvent() => [WatchEvent(event.path, WatchChange.created)],
  FileSystemModifyEvent() => [WatchEvent(event.path, WatchChange.modified)],
  FileSystemDeleteEvent() => [WatchEvent(event.path, WatchChange.deleted)],
  FileSystemMoveEvent(:final destination) => [
    WatchEvent(event.path, WatchChange.deleted),
    if (destination != null) WatchEvent(destination, WatchChange.created),
  ],
};

/// One watch a folder, added and removed as folders come and go.
class _TreeWatcher {
  _TreeWatcher(this.root, this.skip, this.onLimit) {
    _controller = StreamController(
      onListen: () => unawaited(_add(root, initial: true)),
      onCancel: _close,
    );
  }

  final String root;
  final bool Function(String directory)? skip;
  final void Function(String message)? onLimit;
  late final StreamController<WatchEvent> _controller;

  /// By path, in order: the folders under one come right after it.
  final SplayTreeMap<String, StreamSubscription<FileSystemEvent>> _watches =
      SplayTreeMap();
  bool _limited = false;
  bool _closed = false;

  Stream<WatchEvent> get stream => _controller.stream;

  /// How long a crawl reads folders before it lets the isolate go on.
  static const _slice = Duration(milliseconds: 8);

  /// Watches [directory] and the folders under it, a few milliseconds of
  /// them at a time: tens of thousands of folders read at once would hold
  /// up the isolate (heartbeats, replies, a reconnect's handshake) for as
  /// long. Found [initial]ly, the files in them are not news; added later,
  /// they are created.
  Future<void> _add(String directory, {bool initial = false}) async {
    final pending = [directory];
    final slice = Stopwatch()..start();
    while (pending.isNotEmpty) {
      if (slice.elapsed >= _slice) {
        await Future<void>.delayed(Duration.zero);
        slice.reset();
      }
      final folder = pending.removeLast();
      if (!_watch(folder)) continue;
      final List<FileSystemEntity> entries;
      try {
        entries = Directory(folder).listSync(followLinks: false);
      } on FileSystemException {
        continue;
      }
      for (final entry in entries) {
        if (entry is Directory) {
          pending.add(entry.path);
        } else if (!initial) {
          _controller.add(WatchEvent(entry.path, WatchChange.created));
        }
      }
    }
  }

  /// Watches [directory] alone; whether it now is, newly.
  bool _watch(String directory) {
    if (_closed || _limited || _watches.containsKey(directory)) return false;
    if (directory != root && (skip?.call(directory) ?? false)) return false;
    try {
      _watches[directory] = Directory(directory).watch().listen(
        (event) => _event(directory, event),
        onError: (Object error) => _failed(directory, error),
        onDone: () => _watches.remove(directory),
      );
      return true;
    } on FileSystemException catch (error) {
      _failed(directory, error);
      return false;
    }
  }

  void _event(String directory, FileSystemEvent event) {
    if (_closed) return;
    for (final change in _events(event)) {
      _controller.add(change);
      if (change.change == WatchChange.deleted) {
        _removeUnder(change.path);
      }
    }
    final created = switch (event) {
      FileSystemCreateEvent(isDirectory: true) => event.path,
      FileSystemMoveEvent(isDirectory: true, :final destination) => destination,
      _ => null,
    };
    if (created != null) unawaited(_add(created));
  }

  /// Stops watching [path] and the folders under it. One not watched has
  /// none watched under it (a file, a folder skipped): nothing to look
  /// through, as a batch of files renamed would have each time.
  void _removeUnder(String path) {
    if (!_watches.containsKey(path)) return;
    final under = '$path${p.separator}';
    final gone = [path];
    for (
      var key = _watches.firstKeyAfter(under);
      key != null && key.startsWith(under);
      key = _watches.firstKeyAfter(key)
    ) {
      gone.add(key);
    }
    for (final folder in gone) {
      unawaited(_watches.remove(folder)?.cancel());
    }
  }

  void _failed(String directory, Object error) {
    unawaited(_watches.remove(directory)?.cancel());
    // ENOSPC: out of inotify watches. Folders gone meanwhile fail too,
    // and are no news.
    if (error is FileSystemException && error.osError?.errorCode == 28) {
      if (!_limited) {
        _limited = true;
        onLimit?.call(
          'Watching $root stopped at ${_watches.length} folders: the '
          'system allows no more inotify watches (fs.inotify.max_user_watches)',
        );
      }
    }
  }

  Future<void> _close() async {
    _closed = true;
    final watches = [..._watches.values];
    _watches.clear();
    await Future.wait([for (final watch in watches) watch.cancel()]);
  }
}
