import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'ide_file.dart';

/// The files of the project at [root] on this machine: listed, read as
/// text the editor can show, and saved only over what was read (see
/// [IdeFileConflictException]).
class LocalFiles {
  LocalFiles(this.root);

  final String root;

  /// [root] with its links resolved: never deleted.
  late final Future<String> _canonicalRoot = _resolved(root);
  final Map<String, _FileSnapshot> _snapshots = {};
  Future<void> _operations = Future<void>.value();

  static const _maximumFileBytes = 5 * 1024 * 1024;

  /// The limit for files opened anyway.
  static const _forcedMaximumFileBytes = 64 * 1024 * 1024;

  /// VS Code's default `files.exclude`; everything else is listed (ignored
  /// paths dimmed by the Git decorations).
  static const _hiddenDirectories = {'.git', '.svn', '.hg', 'CVS'};
  static const _hiddenFiles = {'.DS_Store', 'Thumbs.db'};

  // Reads and writes share a queue so an old read cannot replace a newer save's
  // baseline. Failed operations must not poison the queue.
  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _operations.then((_) => operation());
    _operations = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  /// [path] with its links resolved. Anywhere, not only in the project: a
  /// file outside it opens and saves as VS Code's do.
  static Future<String> _resolved(String path) async =>
      p.normalize(await File(path).resolveSymbolicLinks());

  static Future<String> _regularFile(String path) async {
    final target = await _resolved(path);
    if (await FileSystemEntity.type(target, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FileSystemException('Only regular files can be edited', path);
    }
    return target;
  }

  Future<List<IdeFile>> list(String directory) async {
    final resolved = await _resolved(directory);
    final entries = await Directory(resolved).list(followLinks: false).toList();
    final files = <IdeFile>[
      for (final entry in entries)
        if (entry is Directory || entry is File)
          if (!(entry is Directory ? _hiddenDirectories : _hiddenFiles)
              .contains(p.basename(entry.path)))
            IdeFile(
              entry.path,
              p.basename(entry.path),
              isDirectory: entry is Directory,
            ),
    ];
    files.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return files;
  }

  Future<String> read(String path, {bool force = false}) =>
      _serialize(() async {
        if (!await File(path).exists()) throw IdeFileNotFoundException(path);
        final resolved = await _regularFile(path);
        final handle = await File(resolved).open();
        final limit = force ? _forcedMaximumFileBytes : _maximumFileBytes;
        void checkSize(int length) => _checkSize(path, length, limit: limit);
        late Uint8List bytes;
        try {
          checkSize(await handle.length());
          // Bound the read itself, not just the earlier stat: files may grow.
          bytes = await handle.read(limit + 1);
          checkSize(bytes.length);
          checkSize(await handle.length());
          if (await _regularFile(path) != resolved) {
            throw IdeFileConflictException(path);
          }
        } finally {
          await handle.close();
        }
        final text = force
            ? utf8.decode(bytes, allowMalformed: true)
            : _decode(path, bytes);
        _snapshots[_key(path)] = _FileSnapshot(
          resolved,
          bytes,
          text,
          RegExp(r'\r\n|\n|\r').firstMatch(text)?.group(0) ?? '\n',
          bytes.length >= 3 &&
              bytes[0] == 0xef &&
              bytes[1] == 0xbb &&
              bytes[2] == 0xbf,
          forced: force,
        );
        return text;
      });

  Future<void> write(String path, String text, {String? expectedText}) =>
      _serialize(() async {
        final snapshot = _snapshots[_key(path)];
        if (snapshot == null) {
          throw StateError('Read the file before saving it: $path');
        }
        final resolved = await _regularFile(path);
        if (snapshot.path != resolved ||
            (expectedText != null && _lf(expectedText) != _lf(snapshot.text))) {
          throw IdeFileConflictException(path);
        }
        // A no-op preserves even mixed line endings byte for byte. Otherwise,
        // retain the original BOM and newline convention, regardless of the
        // line endings emitted by the editor.
        final bytes = _lf(text) == _lf(snapshot.text)
            ? snapshot.bytes
            : Uint8List.fromList([
                if (snapshot.hasBom) ...[0xef, 0xbb, 0xbf],
                ...utf8.encode(_lf(text).replaceAll('\n', snapshot.lineEnding)),
              ]);
        if (!snapshot.forced) {
          _checkSize(path, bytes.length);
          _decode(path, bytes);
        }

        // Compare the complete file before opening it for writing. Opening in
        // FileMode.write would truncate before a conflict could be detected;
        // writeOnly keeps the existing bytes until the comparison is done.
        final current = await File(resolved).readAsBytes();
        if (await _regularFile(path) != resolved ||
            !_sameBytes(current, snapshot.bytes)) {
          throw IdeFileConflictException(path);
        }
        final handle = await File(resolved).open(mode: FileMode.writeOnly);
        var locked = false;
        try {
          await handle.lock(FileLock.blockingExclusive);
          locked = true;
          await handle.setPosition(0);
          await handle.writeFrom(bytes);
          await handle.truncate(bytes.length);
          await handle.flush();
          _snapshots[_key(path)] = _FileSnapshot(
            resolved,
            bytes,
            text,
            snapshot.lineEnding,
            snapshot.hasBom,
            forced: snapshot.forced,
          );
        } finally {
          try {
            if (locked) await handle.unlock();
          } finally {
            await handle.close();
          }
        }
      });

  /// [path] resolved in its (existing) parent; [path] itself need not
  /// exist.
  static Future<String> _newPath(String path) async {
    final parent = await _resolved(p.dirname(path));
    return p.join(parent, p.basename(path));
  }

  static Future<bool> _exists(String path) async =>
      await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound;

  Future<void> create(String path, {bool directory = false}) =>
      _serialize(() async {
        final target = await _newPath(path);
        if (await _exists(target)) throw IdeFileExistsException(path);
        if (directory) {
          await Directory(target).create();
        } else {
          await File(target).create(exclusive: true);
        }
      });

  /// Makes the file [path] of [bytes] (a picture pasted beside a
  /// document); throws [IdeFileExistsException] when [path] exists, and
  /// leaves no part of it when the write fails.
  Future<void> writeBytes(String path, List<int> bytes) => _serialize(() async {
    final target = await _newPath(path);
    final file = File(target);
    try {
      await file.create(exclusive: true);
    } on PathExistsException {
      throw IdeFileExistsException(path);
    } on FileSystemException {
      if (await _exists(target)) throw IdeFileExistsException(path);
      rethrow;
    }
    try {
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {
      await file.delete().catchError((Object _) => file);
      rethrow;
    }
  });

  Future<void> rename(String from, String to) => _serialize(() async {
    final source = await _newPath(from);
    final target = await _newPath(to);
    if (!await _exists(source)) throw IdeFileNotFoundException(from);
    // A change of case only is the same file on case-insensitive disks.
    final sameFile = source.toLowerCase() == target.toLowerCase();
    if (!sameFile && await _exists(target)) {
      throw IdeFileExistsException(to);
    }
    final type = await FileSystemEntity.type(source, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      await Directory(source).rename(target);
    } else if (type == FileSystemEntityType.link) {
      await Link(source).rename(target);
    } else {
      await File(source).rename(target);
    }
    _snapshots.remove(_key(from));
  });

  Future<void> copy(String from, String to) => _serialize(() async {
    final source = await _newPath(from);
    final target = await _newPath(to);
    if (await _exists(target)) throw IdeFileExistsException(to);
    Future<void> copyEntity(String from, String to) async {
      switch (await FileSystemEntity.type(from, followLinks: false)) {
        case FileSystemEntityType.directory:
          await Directory(to).create();
          await for (final entry in Directory(from).list(followLinks: false)) {
            await copyEntity(entry.path, p.join(to, p.basename(entry.path)));
          }
        case FileSystemEntityType.link:
          await Link(to).create(await Link(from).target());
        case FileSystemEntityType.file:
          await File(from).copy(to);
        default:
          throw IdeFileNotFoundException(from);
      }
    }

    await copyEntity(source, target);
  });

  Future<void> delete(String path) => _serialize(() async {
    final target = await _newPath(path);
    if (p.equals(target, p.normalize(await _canonicalRoot))) {
      throw FileSystemException('The project folder cannot be deleted', path);
    }
    final type = await FileSystemEntity.type(target, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw IdeFileNotFoundException(path);
    }
    await (type == FileSystemEntityType.directory
            ? Directory(target)
            : type == FileSystemEntityType.link
            ? Link(target)
            : File(target))
        .delete(recursive: type == FileSystemEntityType.directory);
    _snapshots.remove(_key(path));
  });

  static String _key(String path) => p.normalize(p.absolute(path));

  static String _lf(String text) => text.replaceAll(RegExp(r'\r\n?'), '\n');

  static void _checkSize(
    String path,
    int length, {
    int limit = _maximumFileBytes,
  }) {
    if (length > limit) throw IdeFileTooLargeException(path, length);
  }

  static String _decode(String path, List<int> bytes) {
    if (bytes.any(
      (byte) =>
          (byte < 32 && byte != 9 && byte != 10 && byte != 12 && byte != 13) ||
          byte == 127,
    )) {
      throw IdeBinaryFileException(path);
    }
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw IdeBinaryFileException(path);
    }
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _FileSnapshot {
  const _FileSnapshot(
    this.path,
    this.bytes,
    this.text,
    this.lineEnding,
    this.hasBom, {
    this.forced = false,
  });

  final String path;
  final Uint8List bytes;
  final String text;
  final String lineEnding;
  final bool hasBom;

  /// Opened anyway: saved without the binary and size checks.
  final bool forced;
}

/// [path]'s bytes, whole; throws [IdeFileNotFoundException] when there is
/// no such file.
Future<Uint8List> readFileBytes(String path) async {
  final file = File(path);
  if (!await file.exists()) throw IdeFileNotFoundException(path);
  return file.readAsBytes();
}

/// Changes to the entries of [directory]; empty where it cannot be
/// watched.
Stream<void> watchDirectory(String directory) {
  if (!FileSystemEntity.isWatchSupported) return const Stream.empty();
  try {
    return Directory(directory).watch().map((_) {}).handleError((Object _) {});
  } on FileSystemException {
    return const Stream.empty();
  }
}

/// Every regular file under [root] (Git's list where there is one), off
/// this isolate.
Future<IdeFileListing> walkProjectFiles(
  String root,
  Set<String> excluded,
  int limit,
) => Isolate.run(
  () =>
      _gitProjectFiles(root, excluded, limit) ??
      _walkProjectFiles(root, excluded, limit),
);

/// The files Git sees under [root], tracked or not, without those its
/// ignore files ignore (as VS Code's Quick Open, through ripgrep, honors
/// `.gitignore`); null outside a repository or without Git. Other Git
/// repositories inside (worktrees, clones) are left out, as Git leaves them.
IdeFileListing? _gitProjectFiles(String root, Set<String> excluded, int limit) {
  final ProcessResult result;
  try {
    result = Process.runSync(
      'git',
      [
        '--no-optional-locks',
        '-c',
        'core.fsmonitor=false',
        'ls-files',
        '--cached',
        '--others',
        '--exclude-standard',
        '-z',
      ],
      workingDirectory: root,
      environment: const {
        'GIT_TERMINAL_PROMPT': '0',
        'GIT_OPTIONAL_LOCKS': '0',
      },
      stdoutEncoding: utf8,
    );
  } on ProcessException {
    return null;
  } on FormatException {
    return null;
  }
  if (result.exitCode != 0) return null;
  final paths = <String>[];
  var truncated = false;
  for (final relative in (result.stdout as String).split('\x00')) {
    // Empty after the last NUL; a nested repository shows as `dir/`.
    if (relative.isEmpty || relative.endsWith('/')) continue;
    final parts = relative.split('/');
    if (parts.take(parts.length - 1).any(excluded.contains)) continue;
    final path = p.joinAll([root, ...parts]);
    // Tracked files deleted from the working tree, and submodules, are not
    // files to open.
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.file) {
      continue;
    }
    if (paths.length >= limit) {
      truncated = true;
      break;
    }
    paths.add(path);
  }
  // None: the root may be ignored itself, which Git then lists nothing of.
  if (paths.isEmpty) return null;
  paths.sort();
  return IdeFileListing(paths, truncated: truncated);
}

IdeFileListing _walkProjectFiles(String root, Set<String> excluded, int limit) {
  final paths = <String>[];
  final pending = <String>[root];
  var truncated = false;
  while (pending.isNotEmpty && !truncated) {
    final directory = pending.removeLast();
    final List<FileSystemEntity> entries;
    try {
      entries = Directory(directory).listSync(followLinks: false);
    } on FileSystemException {
      continue;
    }
    for (final entry in entries) {
      final name = p.basename(entry.path);
      if (entry is Directory) {
        if (!excluded.contains(name)) pending.add(p.join(directory, name));
      } else if (entry is File) {
        paths.add(p.join(directory, name));
        if (paths.length >= limit) {
          truncated = true;
          break;
        }
      }
    }
  }
  paths.sort();
  return IdeFileListing(paths, truncated: truncated);
}
