import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'line_diff.dart' as diff;
import 'review_store.dart';

/// [ReviewStore] over a folder of this machine's: each blob a file named
/// by its content's SHA-256 (`blobs/<first two>/<the rest>`), each
/// session's account a file of its own (`sessions/<name>.json`, with the
/// blobs it keeps). What files are put back is byte for byte what they
/// were.
class BlobReviewStore implements ReviewStore {
  BlobReviewStore._(this.checkpoints);

  /// The store in [checkpoints] (made as it is needed), which is tidied
  /// from then on ([scheduleTidy]).
  static BlobReviewStore open(String checkpoints) {
    checkpoints = p.normalize(p.absolute(checkpoints));
    scheduleTidy(checkpoints);
    return _stores.putIfAbsent(
      checkpoints,
      () => BlobReviewStore._(checkpoints),
    );
  }

  static final Map<String, BlobReviewStore> _stores = {};

  /// The folder it keeps everything in.
  final String checkpoints;

  /// Past this size what a file holds is not kept: a change to it is
  /// listed, not undone.
  static int maxFileBytes = 32 * 1024 * 1024;

  /// Past this many bytes, lines are compared on an isolate of their own.
  static const _isolateBytes = 256 * 1024;

  String get _blobs => p.join(checkpoints, 'blobs');
  String get _sessions => p.join(checkpoints, 'sessions');

  String _blobPath(String oid) =>
      p.join(_blobs, oid.substring(0, 2), oid.substring(2));

  static String _hash(List<int> bytes) => sha256.convert(bytes).toString();

  // --- Files -----------------------------------------------------------------

  @override
  Future<ReviewBlob?> take(String path) async {
    final found = await _readAt(path);
    if (found == null) return null;
    return _keep(found.bytes, found.mode);
  }

  @override
  Future<ReviewBlob?> current(String path) async {
    final found = await _readAt(path);
    if (found == null) return null;
    return ReviewBlob(found.mode, _hash(found.bytes));
  }

  /// What is at [path]: a link's target, or a file's bytes.
  Future<({Uint8List bytes, String mode})?> _readAt(String path) async {
    switch (FileSystemEntity.typeSync(path, followLinks: false)) {
      case FileSystemEntityType.notFound || FileSystemEntityType.directory:
        return null;
      case FileSystemEntityType.link:
        final target = await Link(path).target();
        return (bytes: utf8.encode(target), mode: '120000');
      default:
        final file = File(path);
        final stat = await file.stat();
        if (stat.size > maxFileBytes) {
          throw ReviewUnavailable('$path is too large to keep.');
        }
        final bytes = await file.readAsBytes();
        final executable = !Platform.isWindows && stat.mode & 0x49 != 0;
        return (bytes: bytes, mode: executable ? '100755' : '100644');
    }
  }

  Future<ReviewBlob> _keep(Uint8List bytes, String mode) async {
    final oid = _hash(bytes);
    final file = File(_blobPath(oid));
    if (await file.exists()) {
      // Taken again: not collected as one nothing has kept for long.
      try {
        await file.setLastModified(DateTime.now());
      } on FileSystemException {
        // It stays as it was.
      }
    } else {
      await file.parent.create(recursive: true);
      final partial = File('${file.path}.$pid-${_partials++}');
      await partial.writeAsBytes(bytes, flush: true);
      await partial.rename(file.path);
    }
    return ReviewBlob(mode, oid);
  }

  static int _partials = 0;

  @override
  Future<Uint8List> read(ReviewBlob blob) async {
    try {
      return await File(_blobPath(blob.oid)).readAsBytes();
    } on FileSystemException {
      throw const ReviewUnavailable('What the file was is gone.');
    }
  }

  @override
  Future<ReviewBlob> store(Uint8List bytes, {required String mode}) =>
      _keep(bytes, mode);

  @override
  Future<void> restore(String path, ReviewBlob? blob, {String? root}) async {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      throw ReviewUnavailable('$path is a folder now.');
    }
    if (blob == null) {
      if (type != FileSystemEntityType.notFound) await File(path).delete();
      if (root != null) await _removeEmpty(p.dirname(path), root);
      return;
    }
    final bytes = await read(blob);
    if (type == FileSystemEntityType.link ||
        (blob.isLink && type != FileSystemEntityType.notFound)) {
      await File(path).delete();
    }
    await Directory(p.dirname(path)).create(recursive: true);
    if (blob.isLink) {
      await Link(path).create(utf8.decode(bytes, allowMalformed: true));
      return;
    }
    await File(path).writeAsBytes(bytes, flush: true);
    if (blob.mode == '100755' && !Platform.isWindows) {
      await Process.run('chmod', ['+x', path]);
    }
  }

  /// Deletes [directory] and those above it while empty, up to [root].
  static Future<void> _removeEmpty(String directory, String root) async {
    while (p.isWithin(root, directory)) {
      final folder = Directory(directory);
      try {
        if (!await folder.exists() || !await folder.list().isEmpty) return;
        await folder.delete();
      } on FileSystemException {
        return;
      }
      directory = p.dirname(directory);
    }
  }

  @override
  Future<void> write(String path, Uint8List bytes) =>
      File(path).writeAsBytes(bytes, flush: true);

  @override
  Future<Uint8List?> merge(
    ReviewBlob mine,
    ReviewBlob from,
    ReviewBlob to,
  ) async {
    if (mine.isLink || from.isLink || to.isLink) return null;
    final (a, b, c) = (await read(mine), await read(from), await read(to));
    if (a.length + b.length + c.length < _isolateBytes) {
      return diff.merge3(a, b, c);
    }
    return Isolate.run(() => diff.merge3(a, b, c));
  }

  @override
  Future<({int added, int removed})?> lineCounts(
    ReviewBlob? from,
    ReviewBlob? to,
  ) async {
    if (from == to) return (added: 0, removed: 0);
    final before = from == null ? null : await read(from);
    final after = to == null ? null : await read(to);
    if ((before?.length ?? 0) + (after?.length ?? 0) < _isolateBytes) {
      return diff.lineCounts(before, after);
    }
    return Isolate.run(() => diff.lineCounts(before, after));
  }

  // --- Sessions --------------------------------------------------------------

  static final _safeName = RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9._-]*$');

  static String _nameOf(String session) => _safeName.hasMatch(session)
      ? session
      : 'h${_hash(utf8.encode(session)).substring(0, 16)}';

  File _sessionFile(String session) =>
      File(p.join(_sessions, '${_nameOf(session)}.json'));

  /// The sessions loaded or saved in this process, by checkpoints folder:
  /// conversations that may be open, which [clear] leaves.
  static final Map<String, Set<String>> _held = {};

  void _hold(String session) =>
      _held.putIfAbsent(checkpoints, () => {}).add(_nameOf(session));

  @override
  Future<String?> load(String session) async {
    _hold(session);
    final file = _sessionFile(session);
    if (!await file.exists()) return null;
    final json = jsonDecode(await file.readAsString());
    return json is Map ? json['data'] as String? : null;
  }

  @override
  Future<void> save(
    String session,
    String data, {
    required Iterable<ReviewBlob> blobs,
  }) async {
    _hold(session);
    final file = _sessionFile(session);
    await file.parent.create(recursive: true);
    final partial = File('${file.path}.$pid-${_partials++}');
    await partial.writeAsString(
      jsonEncode({
        'data': data,
        'blobs': {for (final blob in blobs) blob.oid}.toList(),
      }),
      flush: true,
    );
    await partial.rename(file.path);
  }

  @override
  Future<void> forget(String session) async {
    _held[checkpoints]?.remove(_nameOf(session));
    try {
      await _sessionFile(session).delete();
    } on FileSystemException {
      // None kept.
    }
  }

  // --- Tidying ---------------------------------------------------------------

  /// How long a session's changes are kept after it last saved them: past
  /// it, they can no longer be reviewed or undone.
  static Duration keepFor = const Duration(days: 30);

  /// How long blobs no session keeps stay, for a conversation at work that
  /// has taken them but not saved them yet.
  static const _grace = Duration(days: 2);

  /// Where [tidy] notes when it last ran, in the checkpoints folder.
  static const _tidiedFile = '.tidied';

  /// Clears out [checkpoints], at most once a [every]: the sessions not
  /// saved for [keepFor] go, and the blobs no session keeps. What an
  /// earlier build left there (its Git repositories) goes too. Never
  /// throws; what it cannot read or delete is left.
  static Future<void> tidy(
    String checkpoints, {
    Duration every = const Duration(days: 1),
    DateTime? now,
  }) async {
    now ??= DateTime.now();
    checkpoints = p.normalize(p.absolute(checkpoints));
    try {
      if (!await Directory(checkpoints).exists()) return;
      final tidied = File(p.join(checkpoints, _tidiedFile));
      if (await tidied.exists() &&
          now.difference(await tidied.lastModified()) < every) {
        return;
      }
      await tidied.writeAsString('${now.toIso8601String()}\n');
      await _sweep(
        checkpoints,
        now: now,
        held: {...?_held[checkpoints]},
        staleBefore: now.subtract(keepFor),
        grace: _grace,
      );
    } on Object {
      // Tried again next time.
    }
  }

  /// Deletes what [checkpoints] keeps but for the sessions loaded or
  /// saved in this process (the conversations open): the changes the
  /// others left can no longer be undone. Never throws; what it cannot
  /// delete is left.
  static Future<void> clear(String checkpoints) async {
    checkpoints = p.normalize(p.absolute(checkpoints));
    try {
      if (!await Directory(checkpoints).exists()) return;
      final now = DateTime.now();
      await _sweep(
        checkpoints,
        now: now,
        held: {...?_held[checkpoints]},
        // Every session not held.
        staleBefore: now.add(const Duration(days: 1)),
        // What a conversation at work took within the hour stays.
        grace: const Duration(hours: 1),
      );
    } on Object {
      // What is left stays.
    }
  }

  /// Deletes the sessions not saved since [staleBefore] (but those
  /// [held]), then the blobs none of the others keep, unless taken within
  /// [grace]; and whatever else is there.
  static Future<void> _sweep(
    String checkpoints, {
    required DateTime now,
    required Set<String> held,
    required DateTime staleBefore,
    required Duration grace,
  }) => Isolate.run(() {
    void delete(FileSystemEntity entity) {
      try {
        entity.deleteSync(recursive: true);
      } on FileSystemException {
        // Next time.
      }
    }

    for (final entry in Directory(checkpoints).listSync(followLinks: false)) {
      final name = p.basename(entry.path);
      if (name != 'blobs' && name != 'sessions' && name != _tidiedFile) {
        delete(entry);
      }
    }
    final kept = <String>{};
    final sessions = Directory(p.join(checkpoints, 'sessions'));
    if (sessions.existsSync()) {
      for (final file in sessions.listSync()) {
        if (file is! File || !file.path.endsWith('.json')) {
          // One being written (or left by a write cut short).
          if (file is File &&
              now.difference(file.statSync().modified) > grace) {
            delete(file);
          }
          continue;
        }
        final name = p.basenameWithoutExtension(file.path);
        if (!held.contains(name) &&
            file.statSync().modified.isBefore(staleBefore)) {
          delete(file);
          continue;
        }
        try {
          final json = jsonDecode(file.readAsStringSync());
          for (final oid in (json as Map)['blobs'] as List) {
            kept.add(oid as String);
          }
        } on Object {
          if (!held.contains(name)) delete(file);
        }
      }
    }
    final blobs = Directory(p.join(checkpoints, 'blobs'));
    if (!blobs.existsSync()) return;
    for (final folder in blobs.listSync()) {
      if (folder is! Directory) {
        delete(folder);
        continue;
      }
      final prefix = p.basename(folder.path);
      var left = 0;
      for (final file in folder.listSync()) {
        final oid = '$prefix${p.basename(file.path)}';
        if (kept.contains(oid) ||
            now.difference(file.statSync().modified) < grace) {
          left++;
          continue;
        }
        delete(file);
      }
      if (left == 0) delete(folder);
    }
  });

  /// The bytes [checkpoints] takes up.
  static Future<int> sizeOf(String checkpoints) => Isolate.run(() {
    var bytes = 0;
    final folder = Directory(checkpoints);
    if (!folder.existsSync()) return 0;
    try {
      for (final entry in folder.listSync(
        recursive: true,
        followLinks: false,
      )) {
        if (entry is File) {
          try {
            bytes += entry.lengthSync();
          } on FileSystemException {
            // Gone since.
          }
        }
      }
    } on FileSystemException {
      // What could be listed.
    }
    return bytes;
  });

  static final Map<String, Timer> _tidying = {};

  /// Has [tidy] run on [checkpoints] a minute from now, then every few
  /// hours (it does its work once a day), for as long as the process runs.
  static void scheduleTidy(String checkpoints) {
    checkpoints = p.normalize(p.absolute(checkpoints));
    if (_tidying.containsKey(checkpoints)) return;
    _tidying[checkpoints] = Timer(const Duration(minutes: 1), () {
      unawaited(tidy(checkpoints));
      _tidying[checkpoints] = Timer.periodic(
        const Duration(hours: 6),
        (_) => unawaited(tidy(checkpoints)),
      );
    });
  }
}
