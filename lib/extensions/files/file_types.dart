/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The file service's types: stats, capabilities, errors, change events
// and file operations, as the extension host's protocol carries them.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/platform/files/common/files.ts (`FileType`, `FilePermission`,
// `FileSystemProviderCapabilities`, `FileSystemProviderErrorCode`,
// `toFileSystemProviderErrorCode`, `FileChangeType`, `FileChangeFilter`,
// `FileOperation`, `FileOperationResult`, `IWatchOptions`),
// src/vs/platform/files/common/watcher.ts (`coalesceEvents`,
// `normalizeWatcherPattern`).
//
// Deviations:
// - Glob patterns are matched with bao_remote's `ideGlob` (a regular
//   expression per pattern), not glob.ts' parser; `when` siblings are
//   not supported in watcher patterns.

import 'package:bao_exthost/bao_exthost.dart';
import 'package:bao_remote/search.dart' show ideGlob;

/// `FileType` (bit flags: a link is also a file or folder).
abstract final class FileType {
  static const unknown = 0;
  static const file = 1;
  static const directory = 2;
  static const symbolicLink = 64;
}

/// `FilePermission`.
abstract final class FilePermission {
  static const readonly = 1;
  static const locked = 2;
}

/// `FileSystemProviderCapabilities`.
abstract final class FileSystemProviderCapabilities {
  static const none = 0;
  static const fileReadWrite = 1 << 1;
  static const fileOpenReadWriteClose = 1 << 2;
  static const fileFolderCopy = 1 << 3;
  static const fileReadStream = 1 << 4;
  static const pathCaseSensitive = 1 << 10;
  static const readonly = 1 << 11;
  static const trash = 1 << 12;
  static const fileWriteUnlock = 1 << 13;
  static const fileAtomicRead = 1 << 14;
  static const fileAtomicWrite = 1 << 15;
  static const fileAtomicDelete = 1 << 16;
  static const fileClone = 1 << 17;
  static const fileRealpath = 1 << 18;
}

/// `FileSystemProviderErrorCode`: [value] is what crosses the protocol.
enum FileSystemProviderErrorCode {
  fileExists('EntryExists'),
  fileNotFound('EntryNotFound'),
  fileNotADirectory('EntryNotADirectory'),
  fileIsADirectory('EntryIsADirectory'),
  fileExceedsStorageQuota('EntryExceedsStorageQuota'),
  fileTooLarge('EntryTooLarge'),
  fileWriteLocked('EntryWriteLocked'),
  noPermissions('NoPermissions'),
  unavailable('Unavailable'),
  unknown('Unknown');

  const FileSystemProviderErrorCode(this.value);

  final String value;

  static FileSystemProviderErrorCode? byValue(String value) {
    for (final code in values) {
      if (code.value == value) return code;
    }
    return null;
  }
}

/// `FileSystemProviderError`: what a provider throws.
final class FileSystemProviderException implements Exception {
  const FileSystemProviderException(this.message, this.code);

  final String message;
  final FileSystemProviderErrorCode code;

  /// `markAsFileSystemProviderError`'s name.
  String get name => '${code.value} (FileSystemError)';

  @override
  String toString() => message;
}

/// `toFileSystemProviderErrorCode`: the code of [error], from a provider
/// of ours or one of an extension's (`<code> (FileSystemError)`).
FileSystemProviderErrorCode toFileSystemProviderErrorCode(Object? error) {
  if (error == null) return FileSystemProviderErrorCode.unknown;
  if (error is FileSystemProviderException) return error.code;
  if (error is RpcRemoteError) {
    final match = RegExp(r'^(.+) \(FileSystemError\)$').firstMatch(error.name);
    final code = match == null
        ? null
        : FileSystemProviderErrorCode.byValue(match[1]!);
    if (code != null &&
        code != FileSystemProviderErrorCode.fileExceedsStorageQuota) {
      return code;
    }
  }
  return FileSystemProviderErrorCode.unknown;
}

/// `FileOperationResult`.
enum FileOperationResult {
  fileIsDirectory,
  fileNotFound,
  fileNotModifiedSince,
  fileModifiedSince,
  fileMoveConflict,
  fileWriteLocked,
  filePermissionDenied,
  fileTooLarge,
  fileInvalidPath,
  fileNotDirectory,
  fileOtherError,
}

/// `FileOperationError`: what the file service throws.
final class FileOperationException implements Exception {
  const FileOperationException(this.message, this.result);

  final String message;
  final FileOperationResult result;

  @override
  String toString() => message;
}

/// `toFileOperationResult`.
FileOperationResult toFileOperationResult(Object error) {
  if (error is FileOperationException) return error.result;
  return switch (toFileSystemProviderErrorCode(error)) {
    FileSystemProviderErrorCode.fileNotFound =>
      FileOperationResult.fileNotFound,
    FileSystemProviderErrorCode.fileIsADirectory =>
      FileOperationResult.fileIsDirectory,
    FileSystemProviderErrorCode.fileNotADirectory =>
      FileOperationResult.fileNotDirectory,
    FileSystemProviderErrorCode.fileWriteLocked =>
      FileOperationResult.fileWriteLocked,
    FileSystemProviderErrorCode.noPermissions =>
      FileOperationResult.filePermissionDenied,
    FileSystemProviderErrorCode.fileExists =>
      FileOperationResult.fileMoveConflict,
    FileSystemProviderErrorCode.fileTooLarge =>
      FileOperationResult.fileTooLarge,
    _ => FileOperationResult.fileOtherError,
  };
}

/// `IStat`.
final class FileStat {
  const FileStat({
    required this.type,
    this.ctime = 0,
    this.mtime = 0,
    this.size = 0,
    this.permissions,
  });

  factory FileStat.fromJson(Map<String, Object?> json) => FileStat(
    type: (json['type'] as num?)?.toInt() ?? FileType.unknown,
    ctime: (json['ctime'] as num?)?.toInt() ?? 0,
    mtime: (json['mtime'] as num?)?.toInt() ?? 0,
    size: (json['size'] as num?)?.toInt() ?? 0,
    permissions: (json['permissions'] as num?)?.toInt(),
  );

  final int type;
  final int ctime;
  final int mtime;
  final int size;
  final int? permissions;

  bool get isFile => type & FileType.file != 0;
  bool get isDirectory => type & FileType.directory != 0;
  bool get isSymbolicLink => type & FileType.symbolicLink != 0;
  bool get readonly => (permissions ?? 0) & FilePermission.readonly != 0;

  Map<String, Object?> toJson() => {
    'type': type,
    'ctime': ctime,
    'mtime': mtime,
    'size': size,
    'permissions': ?permissions,
  };
}

/// `FileChangeType`.
enum FileChangeType { updated, added, deleted }

/// `FileChangeFilter`.
abstract final class FileChangeFilter {
  static const updated = 1 << 1;
  static const added = 1 << 2;
  static const deleted = 1 << 3;
}

/// `IFileChange`.
final class FileChange {
  FileChange(this.resource, this.type);

  final VsUri resource;
  FileChangeType type;

  /// `IFileChangeDto`.
  Map<String, Object?> toJson() => {
    'resource': resource.toJson(),
    'type': type.index,
  };

  static FileChange fromJson(Map<String, Object?> json) => FileChange(
    VsUri.revive((json['resource']! as Map).cast()),
    FileChangeType.values[(json['type']! as num).toInt()],
  );

  @override
  String toString() => 'FileChange(${type.name} $resource)';
}

/// `IRelativePattern`: [pattern] under [base] (a path).
typedef RelativePattern = ({String base, String pattern});

/// `IWatchOptions`.
final class WatchOptions {
  const WatchOptions({
    this.recursive = false,
    this.excludes = const [],
    this.includes,
    this.filter,
  });

  /// From the protocol's JSON (includes as strings or `{base, pattern}`).
  factory WatchOptions.fromJson(Map<String, Object?> json) => WatchOptions(
    recursive: json['recursive'] == true,
    excludes: [for (final e in (json['excludes'] as List?) ?? const []) '$e'],
    includes: switch (json['includes']) {
      final List<Object?> list => [
        for (final i in list)
          switch (i) {
            final String s => s,
            {'base': final String base, 'pattern': final String pattern} => (
              base: base,
              pattern: pattern,
            ),
            _ => '$i',
          },
      ],
      _ => null,
    },
    filter: (json['filter'] as num?)?.toInt(),
  );

  final bool recursive;
  final List<String> excludes;

  /// Strings or [RelativePattern]s.
  final List<Object>? includes;
  final int? filter;

  WatchOptions copyWith({bool? recursive}) => WatchOptions(
    recursive: recursive ?? this.recursive,
    excludes: excludes,
    includes: includes,
    filter: filter,
  );
}

/// `FileOperation`.
enum FileOperation { create, delete, move, copy, write }

/// `SourceTargetPair`.
typedef SourceTargetPair = ({VsUri? source, VsUri target});

Map<String, Object?> sourceTargetPairToJson(SourceTargetPair pair) => {
  if (pair.source case final source?) 'source': source.toJson(),
  'target': pair.target.toJson(),
};

/// A glob over absolute `/` paths (`parse` of a string or relative
/// pattern), [ignoreCase] lowering both sides.
bool Function(String path) parseGlob(
  Object pattern, {
  bool ignoreCase = false,
}) {
  String norm(String s) => ignoreCase ? s.toLowerCase() : s;
  switch (pattern) {
    case (base: final String base, pattern: final String glob):
      final regExp = ideGlob(norm(glob));
      final root = norm(base.replaceAll(r'\', '/'));
      final prefix = root.endsWith('/') ? root : '$root/';
      return (path) {
        final p = norm(path.replaceAll(r'\', '/'));
        if (!p.startsWith(prefix)) return false;
        return regExp.hasMatch(p.substring(prefix.length));
      };
    case final String glob:
      final regExp = ideGlob(norm(glob));
      return (path) => regExp.hasMatch(norm(path.replaceAll(r'\', '/')));
  }
  return (_) => false;
}

/// `normalizeWatcherPattern`: a pattern not starting with `**` and not
/// absolute is relative to [path].
Object normalizeWatcherPattern(String path, Object pattern) {
  if (pattern is String &&
      !pattern.startsWith('**') &&
      !pattern.startsWith('/') &&
      !RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(pattern)) {
    return (base: path, pattern: pattern);
  }
  return pattern;
}

/// `coalesceEvents`: one event per path (a create then delete is none, a
/// delete then create a change), and no deletes under a deleted folder.
List<FileChange> coalesceFileChanges(
  Iterable<FileChange> changes, {
  bool caseSensitive = false,
}) {
  String key(FileChange e) {
    final path = e.resource.path;
    return caseSensitive ? path : path.toLowerCase();
  }

  final coalesced = <FileChange>{};
  final byPath = <String, FileChange>{};
  for (final event in changes) {
    final existing = byPath[key(event)];
    var keep = false;
    if (existing != null) {
      final current = existing.type;
      final next = event.type;
      if (existing.resource.path != event.resource.path &&
          (next == FileChangeType.deleted || next == FileChangeType.added)) {
        keep = true;
      } else if (current == FileChangeType.added &&
          next == FileChangeType.deleted) {
        byPath.remove(key(event));
        coalesced.remove(existing);
      } else if (current == FileChangeType.deleted &&
          next == FileChangeType.added) {
        existing.type = FileChangeType.updated;
      } else if (current == FileChangeType.added &&
          next == FileChangeType.updated) {
        // Keep the create.
      } else {
        existing.type = next;
      }
    } else {
      keep = true;
    }
    if (keep) {
      coalesced.add(event);
      byPath[key(event)] = event;
    }
  }
  final addOrChange = <FileChange>[];
  final deletedPaths = <String>[];
  final deletes = coalesced.where((e) {
    if (e.type != FileChangeType.deleted) {
      addOrChange.add(e);
      return false;
    }
    return true;
  }).toList()..sort((a, b) => a.resource.path.length - b.resource.path.length);
  bool isParent(String path, String candidate) {
    final p = caseSensitive ? path : path.toLowerCase();
    var c = caseSensitive ? candidate : candidate.toLowerCase();
    if (!c.endsWith('/')) c = '$c/';
    return p.startsWith(c);
  }

  final result = <FileChange>[];
  for (final e in deletes) {
    if (deletedPaths.any((d) => isParent(e.resource.path, d))) continue;
    deletedPaths.add(e.resource.path);
    result.add(e);
  }
  return result..addAll(addOrChange);
}
