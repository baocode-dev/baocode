/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// This machine's files, for the `file` scheme.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/platform/files/node/diskFileSystemProvider.ts (`stat`, `readdir`,
// `readFile`, `writeFile`'s create/overwrite checks, `mkdir`, `delete`,
// `rename`, `copy`, `toFileSystemProviderError`),
// src/vs/platform/files/common/diskFileSystemProvider.ts (`watch`: one
// recursive or flat watch per request, excludes, includes and the change
// filter).
//
// Deviations:
// - Watching uses Dart's watchers (bao_remote's `watchRecursively`, one
//   watch per folder on Linux) instead of @parcel/watcher and fs.watch;
//   events are batched for 75ms (the upstream watchers' delay) and
//   coalesced.
// - The Trash is the [DiskFileSystemProvider.trash] given, if any.

import 'dart:async';
import 'dart:io' hide FileStat;
import 'dart:io' as io show FileStat;
import 'dart:typed_data';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:bao_remote/local.dart' show WatchChange, watchRecursively;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import 'file_service.dart';
import 'file_types.dart';

final class DiskFileSystemProvider extends FileSystemProvider {
  DiskFileSystemProvider({
    this.trash,
    this.watchDelay = const Duration(milliseconds: 75),
  });

  /// Moves a path to the Trash; none where there is none.
  final Future<void> Function(String path)? trash;
  final Duration watchDelay;

  @override
  int get capabilities =>
      FileSystemProviderCapabilities.fileReadWrite |
      FileSystemProviderCapabilities.fileFolderCopy |
      FileSystemProviderCapabilities.fileRealpath |
      (Platform.isLinux
          ? FileSystemProviderCapabilities.pathCaseSensitive
          : 0) |
      (trash != null ? FileSystemProviderCapabilities.trash : 0);

  final _changes = StreamController<List<FileChange>>.broadcast();

  @override
  Stream<List<FileChange>> get onDidChangeFile => _changes.stream;

  static String _path(VsUri resource) =>
      resource.fsPath(windows: Platform.isWindows);

  @override
  Future<FileStat> stat(VsUri resource) async {
    final path = _path(resource);
    try {
      final link = await FileSystemEntity.isLink(path);
      final stat = await io.FileStat.stat(path);
      if (stat.type == FileSystemEntityType.notFound) {
        throw FileSystemProviderException(
          "ENOENT: no such file or directory, stat '$path'",
          FileSystemProviderErrorCode.fileNotFound,
        );
      }
      final type = switch (stat.type) {
        FileSystemEntityType.directory => FileType.directory,
        FileSystemEntityType.file => FileType.file,
        _ => FileType.unknown,
      };
      final readonly = !Platform.isWindows && stat.mode & 0x92 == 0;
      return FileStat(
        type: type | (link ? FileType.symbolicLink : 0),
        ctime: stat.changed.millisecondsSinceEpoch,
        mtime: stat.modified.millisecondsSinceEpoch,
        size: stat.size,
        permissions: readonly ? FilePermission.readonly : null,
      );
    } on FileSystemException catch (e) {
      throw toProviderError(e);
    }
  }

  @override
  Future<List<(String, int)>> readdir(VsUri resource) async {
    final path = _path(resource);
    try {
      final result = <(String, int)>[];
      await for (final entity in Directory(path).list(followLinks: false)) {
        var type = switch (entity) {
          Directory() => FileType.directory,
          File() => FileType.file,
          _ => FileType.unknown,
        };
        if (entity is Link) {
          type = FileType.symbolicLink;
          final target = await FileSystemEntity.type(entity.path);
          if (target == FileSystemEntityType.directory) {
            type |= FileType.directory;
          } else if (target == FileSystemEntityType.file) {
            type |= FileType.file;
          }
        }
        result.add((p.basename(entity.path), type));
      }
      return result;
    } on FileSystemException catch (e) {
      throw toProviderError(e);
    }
  }

  @override
  Future<Uint8List> readFile(VsUri resource) async {
    try {
      return await File(_path(resource)).readAsBytes();
    } on FileSystemException catch (e) {
      throw toProviderError(e);
    }
  }

  @override
  Future<void> writeFile(
    VsUri resource,
    Uint8List content, {
    bool create = true,
    bool overwrite = true,
  }) async {
    final path = _path(resource);
    try {
      final exists = await File(path).exists();
      if (exists && !overwrite) {
        throw const FileSystemProviderException(
          'File already exists',
          FileSystemProviderErrorCode.fileExists,
        );
      }
      if (!exists && !create) {
        throw const FileSystemProviderException(
          'File not found',
          FileSystemProviderErrorCode.fileNotFound,
        );
      }
      await File(path).writeAsBytes(content, flush: true);
    } on FileSystemException catch (e) {
      throw toProviderError(e);
    }
  }

  @override
  Future<void> mkdir(VsUri resource) async {
    final path = _path(resource);
    try {
      if (await FileSystemEntity.type(path) != FileSystemEntityType.notFound) {
        throw FileSystemProviderException(
          "EEXIST: file already exists, mkdir '$path'",
          FileSystemProviderErrorCode.fileExists,
        );
      }
      await Directory(path).create();
    } on FileSystemException catch (e) {
      throw toProviderError(e);
    }
  }

  @override
  Future<void> delete(
    VsUri resource, {
    bool recursive = false,
    bool useTrash = false,
  }) async {
    final path = _path(resource);
    try {
      if (useTrash && trash != null) {
        await trash!(path);
        return;
      }
      final type = await FileSystemEntity.type(path, followLinks: false);
      switch (type) {
        case FileSystemEntityType.notFound:
          throw FileSystemProviderException(
            "ENOENT: no such file or directory, unlink '$path'",
            FileSystemProviderErrorCode.fileNotFound,
          );
        case FileSystemEntityType.directory:
          await Directory(path).delete(recursive: recursive);
        case FileSystemEntityType.link:
          await Link(path).delete();
        default:
          await File(path).delete();
      }
    } on FileSystemException catch (e) {
      throw toProviderError(e);
    }
  }

  @override
  Future<void> rename(VsUri from, VsUri to, {bool overwrite = false}) async {
    final source = _path(from);
    final target = _path(to);
    if (source == target) return;
    try {
      // Upstream's `validateMoveCopy`: a different-case rename on a
      // case-insensitive disk is a rename, not an overwrite.
      final sameIgnoringCase = source.toLowerCase() == target.toLowerCase();
      if (!sameIgnoringCase &&
          await FileSystemEntity.type(target, followLinks: false) !=
              FileSystemEntityType.notFound) {
        if (!overwrite) {
          throw const FileSystemProviderException(
            'File at target already exists',
            FileSystemProviderErrorCode.fileExists,
          );
        }
        await delete(to, recursive: true);
      }
      final type = await FileSystemEntity.type(source, followLinks: false);
      switch (type) {
        case FileSystemEntityType.notFound:
          throw FileSystemProviderException(
            "ENOENT: no such file or directory, rename '$source'",
            FileSystemProviderErrorCode.fileNotFound,
          );
        case FileSystemEntityType.directory:
          await Directory(source).rename(target);
        case FileSystemEntityType.link:
          await Link(source).rename(target);
        default:
          await File(source).rename(target);
      }
    } on FileSystemException catch (e) {
      throw toProviderError(e);
    }
  }

  @override
  Future<void> copy(VsUri from, VsUri to, {bool overwrite = false}) async {
    final source = _path(from);
    final target = _path(to);
    if (source == target) return;
    try {
      if (await FileSystemEntity.type(target, followLinks: false) !=
          FileSystemEntityType.notFound) {
        if (!overwrite) {
          throw const FileSystemProviderException(
            'File at target already exists',
            FileSystemProviderErrorCode.fileExists,
          );
        }
        await delete(to, recursive: true);
      }
      await _copy(source, target);
    } on FileSystemException catch (e) {
      throw toProviderError(e);
    }
  }

  Future<void> _copy(String source, String target) async {
    switch (await FileSystemEntity.type(source, followLinks: false)) {
      case FileSystemEntityType.notFound:
        throw FileSystemProviderException(
          "ENOENT: no such file or directory, copy '$source'",
          FileSystemProviderErrorCode.fileNotFound,
        );
      case FileSystemEntityType.directory:
        await Directory(target).create();
        await for (final entity in Directory(source).list(followLinks: false)) {
          await _copy(entity.path, p.join(target, p.basename(entity.path)));
        }
      case FileSystemEntityType.link:
        await Link(target).create(await Link(source).target());
      default:
        await File(source).copy(target);
    }
  }

  /// Reports changes as a watch would: used by tests (a real one comes
  /// from the watchers above).
  @visibleForTesting
  void fireChanges(List<FileChange> changes) => _changes.add(changes);

  @visibleForTesting
  void clearChanges() {}

  /// `toFileSystemProviderError`.
  static FileSystemProviderException toProviderError(FileSystemException e) {
    final code = switch (e) {
      PathNotFoundException() => FileSystemProviderErrorCode.fileNotFound,
      PathExistsException() => FileSystemProviderErrorCode.fileExists,
      PathAccessException() => FileSystemProviderErrorCode.noPermissions,
      _ => switch (e.osError?.errorCode) {
        2 => FileSystemProviderErrorCode.fileNotFound,
        17 => FileSystemProviderErrorCode.fileExists,
        20 => FileSystemProviderErrorCode.fileNotADirectory,
        21 => FileSystemProviderErrorCode.fileIsADirectory,
        1 || 13 => FileSystemProviderErrorCode.noPermissions,
        _ => FileSystemProviderErrorCode.unknown,
      },
    };
    return FileSystemProviderException(
      '${e.message}${e.path == null ? '' : ", '${e.path}'"}'
      '${e.osError == null ? '' : ' (${e.osError!.message})'}',
      code,
    );
  }

  // --- watching

  /// The correlated watchers' listeners, for tests.
  @visibleForTesting
  final correlatedListeners = <void Function(List<FileChange>)>[];

  @override
  void Function() watch(
    VsUri resource,
    WatchOptions options, {
    void Function(List<FileChange> changes)? correlated,
  }) {
    if (correlated != null) correlatedListeners.add(correlated);
    final root = _path(resource);
    final ignoreCase = !Platform.isLinux;
    final excludes = [
      for (final e in options.excludes)
        parseGlob(normalizeWatcherPattern(root, e), ignoreCase: ignoreCase),
    ];
    final includes = options.includes == null || options.includes!.isEmpty
        ? null
        : [
            for (final i in options.includes!)
              parseGlob(
                normalizeWatcherPattern(root, i),
                ignoreCase: ignoreCase,
              ),
          ];
    bool excluded(String path) {
      final posix = path.replaceAll(r'\', '/');
      return excludes.any((m) => m(posix));
    }

    final pending = <FileChange>[];
    Timer? timer;
    void report(String path, FileChangeType type) {
      if (path != root && excluded(path)) return;
      if (includes != null &&
          !includes.any((m) => m(path.replaceAll(r'\', '/')))) {
        return;
      }
      final filter = options.filter;
      if (filter != null) {
        final bit = switch (type) {
          FileChangeType.updated => FileChangeFilter.updated,
          FileChangeType.added => FileChangeFilter.added,
          FileChangeType.deleted => FileChangeFilter.deleted,
        };
        if (filter & bit == 0) return;
      }
      pending.add(
        FileChange(VsUri.file(path, windows: Platform.isWindows), type),
      );
      timer ??= Timer(watchDelay, () {
        timer = null;
        final batch = coalesceFileChanges([
          ...pending,
        ], caseSensitive: Platform.isLinux);
        pending.clear();
        if (batch.isEmpty) return;
        if (correlated != null) {
          correlated(batch);
        } else if (!_changes.isClosed) {
          _changes.add(batch);
        }
      });
    }

    StreamSubscription<Object?>? subscription;
    final isDirectory = FileSystemEntity.isDirectorySync(root);
    if (options.recursive && isDirectory) {
      subscription =
          watchRecursively(
            root,
            skip: (directory) => excluded(directory),
          ).listen((event) {
            report(event.path, switch (event.change) {
              WatchChange.created => FileChangeType.added,
              WatchChange.modified => FileChangeType.updated,
              WatchChange.deleted => FileChangeType.deleted,
            });
          });
    } else if (FileSystemEntity.isWatchSupported) {
      // A flat watch: a folder's entries, or one file (through its folder,
      // which survives the file being replaced).
      final folder = isDirectory ? root : p.dirname(root);
      try {
        subscription = Directory(folder)
            .watch()
            .handleError((Object _) {})
            .listen((event) {
              for (final (path, type) in _flatEvents(event)) {
                if (!isDirectory && path != root) continue;
                if (isDirectory && p.dirname(path) != root && path != root) {
                  continue;
                }
                report(path, type);
              }
            });
      } on FileSystemException {
        // Gone: nothing to watch.
      }
    }
    return () {
      timer?.cancel();
      unawaited(subscription?.cancel());
    };
  }

  static Iterable<(String, FileChangeType)> _flatEvents(
    FileSystemEvent event,
  ) => switch (event) {
    FileSystemCreateEvent() => [(event.path, FileChangeType.added)],
    FileSystemModifyEvent() => [(event.path, FileChangeType.updated)],
    FileSystemDeleteEvent() => [(event.path, FileChangeType.deleted)],
    FileSystemMoveEvent(:final destination) => [
      (event.path, FileChangeType.deleted),
      if (destination != null) (destination, FileChangeType.added),
    ],
  };

  void dispose() => unawaited(_changes.close());
}
