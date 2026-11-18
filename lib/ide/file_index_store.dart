import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'file_service.dart';
import 'ide_quick_open.dart' show scoreFilePath;

/// A file of a listing: its path as Quick Open shows it (relative, `/`
/// between, after its folder's name in a multi-folder workspace), the
/// folder it is in (an index into those listed), and its absolute path
/// where it is in none of them.
typedef FileIndexEntry = ({String relative, int folder, String? absolute});

/// [FileIndexEntry.folder] of a file in none of the folders listed.
const fileIndexNoFolder = 0xffff;

/// A project's files packed for matching: their relative paths' UTF-8 one
/// after another, sorted, about as many bytes a file as its path has (a
/// [String] each would take twice that and more).
class FileIndexStore {
  factory FileIndexStore(List<FileIndexEntry> entries) {
    entries.sort((a, b) => a.relative.compareTo(b.relative));
    final count = entries.length;
    final ascii = Uint8List(count);
    final encoded = <int, Uint8List>{};
    var total = 0;
    for (var i = 0; i < count; i++) {
      final relative = entries[i].relative;
      if (_isAscii(relative)) {
        ascii[i] = 1;
        total += relative.length;
      } else {
        final bytes = utf8.encode(relative);
        encoded[i] = bytes;
        total += bytes.length;
      }
    }
    final bytes = Uint8List(total);
    final starts = Uint32List(count + 1);
    final folders = Uint16List(count);
    final absolute = <int, String>{};
    var at = 0;
    for (var i = 0; i < count; i++) {
      final entry = entries[i];
      starts[i] = at;
      folders[i] = entry.folder;
      if (entry.absolute case final path?) absolute[i] = path;
      if (encoded[i] case final utf?) {
        bytes.setRange(at, at + utf.length, utf);
        at += utf.length;
      } else {
        final relative = entry.relative;
        for (var j = 0; j < relative.length; j++) {
          bytes[at++] = relative.codeUnitAt(j);
        }
      }
    }
    starts[count] = at;
    return FileIndexStore._(bytes, starts, ascii, folders, absolute);
  }

  FileIndexStore._(
    this._bytes,
    this._starts,
    this._ascii,
    this._folders,
    this._absolute,
  );

  final Uint8List _bytes;

  /// Where each path starts in [_bytes], and where the last ends.
  final Uint32List _starts;

  /// 1 where a path is ASCII: read back without decoding.
  final Uint8List _ascii;
  final Uint16List _folders;
  final Map<int, String> _absolute;

  int get length => _ascii.length;

  static bool _isAscii(String text) {
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) >= 0x80) return false;
    }
    return true;
  }

  String _relativeAt(int i) {
    final start = _starts[i], end = _starts[i + 1];
    if (_ascii[i] == 1) return String.fromCharCodes(_bytes, start, end);
    return utf8.decode(Uint8List.sublistView(_bytes, start, end));
  }

  FileIndexEntry entryAt(int i) =>
      (relative: _relativeAt(i), folder: _folders[i], absolute: _absolute[i]);

  /// Every entry, in order.
  List<FileIndexEntry> get entries => [
    for (var i = 0; i < length; i++) entryAt(i),
  ];

  /// The first [limit] entries.
  List<FileIndexEntry> head(int limit) => [
    for (var i = 0; i < length && i < limit; i++) entryAt(i),
  ];

  /// The last filter, and the paths it matched: a filter typed on from it
  /// matches only among those.
  String _lastFilter = '';
  Int32List? _lastMatches;

  /// The paths matching [filter] (see [scoreFilePath]), best first, at most
  /// [limit]; the first [limit] for no filter.
  List<FileIndexEntry> find(String filter, int limit) {
    if (filter.isEmpty) return head(limit);
    final last = _lastMatches;
    final narrowing = last != null && filter.startsWith(_lastFilter);
    final count = narrowing ? last.length : length;
    final needle = _asciiLowered(filter);
    final matched = <int>[];
    final best = _Best(limit);
    for (var k = 0; k < count; k++) {
      final i = narrowing ? last[k] : k;
      if (!_mayMatch(i, needle)) continue;
      final result = scoreFilePath(filter, _relativeAt(i));
      if (result == null) continue;
      matched.add(i);
      best.offer(i, result.score, _starts[i + 1] - _starts[i]);
    }
    _lastFilter = filter;
    _lastMatches = Int32List.fromList(matched);
    return [for (final i in best.sorted()) entryAt(i)];
  }

  /// [filter]'s ASCII characters lowercased: a path matching it has them
  /// in order (any case), whatever it has of the rest.
  static Uint8List _asciiLowered(String filter) {
    final bytes = <int>[];
    for (var i = 0; i < filter.length; i++) {
      final unit = filter.codeUnitAt(i);
      if (unit < 0x80) bytes.add(_lower(unit));
    }
    return Uint8List.fromList(bytes);
  }

  static int _lower(int unit) =>
      unit >= 0x41 && unit <= 0x5a ? unit + 0x20 : unit;

  /// Whether path [i] has [needle] in order: the cheap test before scoring,
  /// on the bytes, not decoded.
  bool _mayMatch(int i, Uint8List needle) {
    var k = 0;
    final n = needle.length;
    if (n == 0) return true;
    final end = _starts[i + 1];
    for (var j = _starts[i]; j < end; j++) {
      if (_lower(_bytes[j]) == needle[k] && ++k == n) return true;
    }
    return false;
  }

  /// The folders the paths are in, each once, of the folder of the first
  /// path in it: found once.
  List<FileIndexEntry>? _folderEntries;

  List<FileIndexEntry> _foldersOf() {
    final seen = <String>{};
    final folders = <FileIndexEntry>[];
    for (var i = 0; i < length; i++) {
      // In none of the folders listed: no folder of it to offer.
      if (_folders[i] == fileIndexNoFolder) continue;
      var relative = _relativeAt(i);
      while (true) {
        final cut = relative.lastIndexOf('/');
        if (cut <= 0) break;
        relative = relative.substring(0, cut);
        // Its own folders were seen with it.
        if (!seen.add(relative)) break;
        folders.add((relative: relative, folder: _folders[i], absolute: null));
      }
    }
    return folders;
  }

  /// The folders whose paths match [filter] scoring [minScore] or more,
  /// the best [limit], best first.
  List<({FileIndexEntry entry, int score})> findFolders(
    String filter,
    int limit,
    int minScore,
  ) {
    final found = <({FileIndexEntry entry, int score})>[
      for (final entry in _folderEntries ??= _foldersOf())
        if (scoreFilePath(filter, entry.relative)
            case (:final score, label: _, description: _)
            when score >= minScore)
          (entry: entry, score: score),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return found.take(limit).toList();
  }
}

/// The best [limit] of the paths offered: a heap whose top is the worst
/// kept. Better is a higher score, then a shorter path, then the first.
class _Best {
  _Best(this.limit);

  final int limit;
  final _index = <int>[];
  final _score = <int>[];
  final _length = <int>[];

  bool _better(int a, int b) {
    if (_score[a] != _score[b]) return _score[a] > _score[b];
    if (_length[a] != _length[b]) return _length[a] < _length[b];
    return _index[a] < _index[b];
  }

  void _swap(int a, int b) {
    for (final list in [_index, _score, _length]) {
      final t = list[a];
      list[a] = list[b];
      list[b] = t;
    }
  }

  void offer(int index, int score, int length) {
    if (limit <= 0) return;
    if (_index.length < limit) {
      _index.add(index);
      _score.add(score);
      _length.add(length);
      // Up while its parent is better: the worst on top.
      var at = _index.length - 1;
      while (at > 0) {
        final parent = (at - 1) >> 1;
        if (!_better(parent, at)) break;
        _swap(parent, at);
        at = parent;
      }
      return;
    }
    // No better than the worst kept.
    final top = _score[0];
    if (score < top ||
        (score == top &&
            (length > _length[0] ||
                (length == _length[0] && index > _index[0])))) {
      return;
    }
    _index[0] = index;
    _score[0] = score;
    _length[0] = length;
    var at = 0;
    while (true) {
      final left = at * 2 + 1, right = left + 1;
      var worst = at;
      if (left < _index.length && _better(worst, left)) worst = left;
      if (right < _index.length && _better(worst, right)) worst = right;
      if (worst == at) break;
      _swap(at, worst);
      at = worst;
    }
  }

  /// The indices kept, best first.
  List<int> sorted() {
    final order = List<int>.generate(_index.length, (i) => i)
      ..sort((a, b) => _better(a, b) ? -1 : (_better(b, a) ? 1 : 0));
    return [for (final i in order) _index[i]];
  }
}

/// The files of [folders] on this machine (each relative after its
/// [prefixes]' entry), at most [limit]: listed on the calling isolate.
({List<FileIndexEntry> entries, bool truncated}) listLocalFileEntries(
  List<String> folders,
  List<String> prefixes,
  int limit,
) {
  final entries = <FileIndexEntry>[];
  var truncated = false;
  for (var i = 0; i < folders.length; i++) {
    final folder = folders[i];
    final listing = listLocalProjectFiles(folder, limit - entries.length);
    truncated = truncated || listing.truncated;
    for (final path in listing.paths) {
      entries.add((
        relative: '${prefixes[i]}${_relativeTo(folder, path)}',
        folder: i,
        absolute: null,
      ));
    }
    if (entries.length >= limit) break;
  }
  return (entries: entries, truncated: truncated);
}

/// [path] (in [folder]) relative to it, `/` between, as
/// `IdeFileIndex.relativeOf` has it.
String _relativeTo(String folder, String path) {
  final separator = p.separator;
  String relative;
  if (path.length > folder.length &&
      path.startsWith(folder) &&
      !folder.endsWith(separator) &&
      path.startsWith(separator, folder.length)) {
    relative = path.substring(folder.length + 1);
  } else {
    relative = p.relative(path, from: folder);
  }
  return separator == '/' ? relative : relative.replaceAll(separator, '/');
}

/// A [FileIndexStore] kept on an isolate of its own: a large project's
/// paths stay off the UI isolate, and each filter goes there and the best
/// few come back.
class FileIndexWorker {
  FileIndexWorker._(
    this._isolate,
    this._requests,
    this._replies,
    this._pending,
  );

  static Future<FileIndexWorker> spawn() async {
    final replies = ReceivePort();
    final isolate = await Isolate.spawn(
      _main,
      replies.sendPort,
      debugName: 'file index',
    );
    final pending = <int, Completer<Object?>>{};
    final ready = Completer<SendPort>();
    replies.listen((message) {
      if (message is SendPort) {
        ready.complete(message);
        return;
      }
      final (id, ok, value) = message as (int, bool, Object?);
      final completer = pending.remove(id);
      if (completer == null) return;
      if (ok) {
        completer.complete(value);
      } else {
        completer.completeError(StateError('$value'));
      }
    });
    return FileIndexWorker._(isolate, await ready.future, replies, pending);
  }

  final Isolate _isolate;
  final SendPort _requests;
  final ReceivePort _replies;
  final Map<int, Completer<Object?>> _pending;
  var _nextId = 0;
  var _disposed = false;

  Future<T> _ask<T>(Object request) async {
    if (_disposed) throw StateError('The file index worker is gone');
    final id = _nextId++;
    final completer = _pending[id] = Completer<Object?>();
    _requests.send((id, request));
    return await completer.future as T;
  }

  /// Lists [folders] there (see [listLocalFileEntries]) and keeps them;
  /// all of them come back when no more than [returnAtMost], kept here
  /// then, else the first [head].
  Future<
    ({
      int count,
      bool truncated,
      List<FileIndexEntry> head,
      List<FileIndexEntry>? all,
    })
  >
  listLocal(
    List<String> folders,
    List<String> prefixes, {
    required int limit,
    required int head,
    required int returnAtMost,
  }) => _ask(('listLocal', folders, prefixes, limit, head, returnAtMost));

  /// Keeps [entries] there, in place of any kept.
  Future<void> load(List<FileIndexEntry> entries) => _ask(('load', entries));

  /// [FileIndexStore.find] there.
  Future<List<FileIndexEntry>> find(String filter, int limit) =>
      _ask(('find', filter, limit));

  /// [FileIndexStore.findFolders] there.
  Future<List<({FileIndexEntry entry, int score})>> findFolders(
    String filter,
    int limit,
    int minScore,
  ) => _ask(('folders', filter, limit, minScore));

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _isolate.kill(priority: Isolate.immediate);
    _replies.close();
    for (final completer in _pending.values) {
      completer.completeError(StateError('The file index worker is gone'));
    }
    _pending.clear();
  }

  static void _main(SendPort replies) {
    final requests = ReceivePort();
    replies.send(requests.sendPort);
    FileIndexStore? store;
    requests.listen((message) {
      final (id, request) = message as (int, Object);
      try {
        final Object? reply;
        switch (request) {
          case (
            'listLocal',
            final List<String> folders,
            final List<String> prefixes,
            final int limit,
            final int head,
            final int returnAtMost,
          ):
            final listing = listLocalFileEntries(folders, prefixes, limit);
            final kept = store = FileIndexStore(listing.entries);
            final all = kept.length <= returnAtMost;
            if (all) store = null;
            reply = (
              count: kept.length,
              truncated: listing.truncated,
              head: kept.head(head),
              all: all ? kept.entries : null,
            );
          case ('load', final List<FileIndexEntry> entries):
            store = FileIndexStore(entries);
            reply = null;
          case ('find', final String filter, final int limit):
            reply = store?.find(filter, limit) ?? const <FileIndexEntry>[];
          case (
            'folders',
            final String filter,
            final int limit,
            final int minScore,
          ):
            reply =
                store?.findFolders(filter, limit, minScore) ??
                const <({FileIndexEntry entry, int score})>[];
          default:
            throw ArgumentError('$request');
        }
        replies.send((id, true, reply));
      } catch (error) {
        replies.send((id, false, '$error'));
      }
    });
  }
}
