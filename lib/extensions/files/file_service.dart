/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The files of every scheme, by the provider registered for it: `file`
// (the disk, or a remote project's host), and those extensions register
// (`registerFileSystemProvider`), activated on `onFileSystem:<scheme>`.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/platform/files/common/fileService.ts (`registerProvider`,
// `activateProvider`, `withProvider`, `stat`, `resolve`, `readFile`,
// `writeFile`, `move`, `copy`, `doMoveCopy`, `doValidateMoveCopy`,
// `createFolder`, `mkdirp`, `del`, `doValidateDelete`, `watch`,
// `createWatcher`).
//
// Deviations:
// - Whole buffers only: no streams, no open/read/write/close transfers,
//   no etag/mtime dirty-write checks, no atomic writes or unlocking.
// - Uncorrelated changes are batched for [FileService.batchDelay] and
//   coalesced, so overlapping watches (the workspace's and an
//   extension's) report a change once, as the universal watcher's
//   request normalization does upstream.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:flutter/foundation.dart';

import 'file_types.dart';

/// `IFileSystemProvider`: the files of one scheme.
abstract class FileSystemProvider {
  /// [FileSystemProviderCapabilities].
  int get capabilities;

  /// Changes its watches saw that no correlated watch asked for.
  Stream<List<FileChange>> get onDidChangeFile;

  Future<FileStat> stat(VsUri resource);

  /// Names and [FileType]s of a folder's entries.
  Future<List<(String, int)>> readdir(VsUri resource);

  Future<Uint8List> readFile(VsUri resource);

  Future<void> writeFile(
    VsUri resource,
    Uint8List content, {
    bool create = true,
    bool overwrite = true,
  });

  Future<void> mkdir(VsUri resource);

  Future<void> delete(
    VsUri resource, {
    bool recursive = false,
    bool useTrash = false,
  });

  Future<void> rename(VsUri from, VsUri to, {bool overwrite = false});

  /// Only with [FileSystemProviderCapabilities.fileFolderCopy].
  Future<void> copy(VsUri from, VsUri to, {bool overwrite = false}) =>
      throw UnsupportedError('copy');

  /// Watches [resource]; the returned function stops. Changes go to
  /// [correlated] when given (only it sees them), else [onDidChangeFile].
  void Function() watch(
    VsUri resource,
    WatchOptions options, {
    void Function(List<FileChange> changes)? correlated,
  });
}

/// `IFileStat` (what [FileService.resolve] answers): a folder with its
/// [children].
final class ResolvedFileStat {
  const ResolvedFileStat(this.resource, this.stat, {this.children});

  final VsUri resource;
  final FileStat stat;
  final List<ResolvedFileStat>? children;

  String get name => uriBasename(resource);
  bool get isFile => stat.isFile;
  bool get isDirectory => stat.isDirectory;
  bool get isSymbolicLink => stat.isSymbolicLink;
  bool get readonly => stat.readonly;
}

/// A provider registered or gone: [capabilities] null when gone.
typedef FileSystemProviderRegistration = ({String scheme, int? capabilities});

/// Activates the extensions that provide [scheme]'s files.
typedef FileSystemActivator = Future<void> Function(String scheme);

/// `IFileService`.
final class FileService {
  FileService({this.batchDelay = const Duration(milliseconds: 50)});

  final Duration batchDelay;

  final _providers = <String, FileSystemProvider>{};
  final _providerSubscriptions = <String, StreamSubscription<void>>{};
  final _activators = <FileSystemActivator>[];
  final _registrations =
      StreamController<FileSystemProviderRegistration>.broadcast(sync: true);
  final _changes = StreamController<List<FileChange>>.broadcast();
  final _pending = <FileChange>[];
  Timer? _flush;

  /// `onDidChangeFileSystemProviderRegistrations`.
  Stream<FileSystemProviderRegistration> get onDidChangeRegistrations =>
      _registrations.stream;

  /// `onDidFilesChange`: the uncorrelated changes all watches saw.
  Stream<List<FileChange>> get onDidFilesChange => _changes.stream;

  /// Has [provider] serve [scheme] until the returned function is called.
  void Function() registerProvider(String scheme, FileSystemProvider provider) {
    if (_providers.containsKey(scheme)) {
      throw StateError(
        "A filesystem provider for the scheme '$scheme' is already registered.",
      );
    }
    _providers[scheme] = provider;
    _providerSubscriptions[scheme] = provider.onDidChangeFile.listen(
      (changes) => _fire(changes, provider),
    );
    _registrations.add((scheme: scheme, capabilities: provider.capabilities));
    return () {
      if (!identical(_providers[scheme], provider)) return;
      _providers.remove(scheme);
      unawaited(_providerSubscriptions.remove(scheme)?.cancel());
      _registrations.add((scheme: scheme, capabilities: null));
    };
  }

  /// Lets [activator] join every activation of a scheme's provider
  /// (`onWillActivateFileSystemProvider`), until the returned function is
  /// called.
  void Function() addActivator(FileSystemActivator activator) {
    _activators.add(activator);
    return () => _activators.remove(activator);
  }

  FileSystemProvider? getProvider(String scheme) => _providers[scheme];

  bool hasProvider(VsUri resource) => _providers.containsKey(resource.scheme);

  bool hasCapability(VsUri resource, int capability) =>
      (_providers[resource.scheme]?.capabilities ?? 0) & capability != 0;

  /// `listCapabilities`.
  Iterable<FileSystemProviderRegistration> listCapabilities() => [
    for (final MapEntry(:key, :value) in _providers.entries)
      (scheme: key, capabilities: value.capabilities),
  ];

  /// `activateProvider`: the activators join; returns at once when the
  /// provider is there.
  Future<void> activateProvider(String scheme) async {
    final joiners = [
      for (final activate in [..._activators])
        Future.sync(() => activate(scheme)).catchError((Object _) {}),
    ];
    if (_providers.containsKey(scheme)) return;
    await Future.wait(joiners);
  }

  /// `canHandleResource`.
  Future<bool> canHandleResource(VsUri resource) async {
    await activateProvider(resource.scheme);
    return hasProvider(resource);
  }

  Future<FileSystemProvider> _withProvider(VsUri resource) async {
    if (!resource.path.startsWith('/')) {
      throw FileOperationException(
        "Unable to resolve filesystem provider with relative file path "
        "'${_forError(resource)}'",
        FileOperationResult.fileInvalidPath,
      );
    }
    await activateProvider(resource.scheme);
    final provider = _providers[resource.scheme];
    if (provider == null) {
      throw NoFileSystemProviderException(resource);
    }
    return provider;
  }

  Future<FileSystemProvider> _withWriteProvider(VsUri resource) async {
    final provider = await _withProvider(resource);
    if (provider.capabilities & FileSystemProviderCapabilities.readonly != 0) {
      throw FileOperationException(
        "Unable to modify read-only file '${_forError(resource)}'",
        FileOperationResult.filePermissionDenied,
      );
    }
    return provider;
  }

  // --- stat

  /// `stat`: throws [FileOperationException]s.
  Future<FileStat> stat(VsUri resource) async {
    final provider = await _withProvider(resource);
    try {
      return await provider.stat(resource);
    } on Object catch (error) {
      throw _resolveError(resource, error);
    }
  }

  /// `resolve`: [resource]'s stat, with a folder's children.
  Future<ResolvedFileStat> resolve(VsUri resource) async {
    final provider = await _withProvider(resource);
    try {
      final stat = await provider.stat(resource);
      if (!stat.isDirectory) return ResolvedFileStat(resource, stat);
      final entries = await provider.readdir(resource);
      final children = <ResolvedFileStat>[];
      for (final (name, type) in entries) {
        final child = uriJoin(resource, name);
        FileStat childStat;
        try {
          childStat = await provider.stat(child);
        } on Object {
          childStat = FileStat(type: type);
        }
        children.add(ResolvedFileStat(child, childStat));
      }
      return ResolvedFileStat(resource, stat, children: children);
    } on Object catch (error) {
      throw _resolveError(resource, error);
    }
  }

  Object _resolveError(VsUri resource, Object error) {
    if (error is FileOperationException) return error;
    if (toFileSystemProviderErrorCode(error) ==
        FileSystemProviderErrorCode.fileNotFound) {
      return FileOperationException(
        "Unable to resolve nonexistent file '${_forError(resource)}'",
        FileOperationResult.fileNotFound,
      );
    }
    return error;
  }

  Future<bool> exists(VsUri resource) async {
    final provider = await _withProvider(resource);
    try {
      await provider.stat(resource);
      return true;
    } on Object {
      return false;
    }
  }

  // --- read and write

  Future<Uint8List> readFile(VsUri resource) async {
    final provider = await _withProvider(resource);
    try {
      final stat = await provider.stat(resource);
      if (stat.isDirectory) {
        throw FileOperationException(
          "Unable to read file '${_forError(resource)}' that is actually a "
          'directory',
          FileOperationResult.fileIsDirectory,
        );
      }
      return await provider.readFile(resource);
    } on Object catch (error) {
      throw FileOperationException(
        "Unable to read file '${_forError(resource)}' (${_describe(error)})",
        toFileOperationResult(error),
      );
    }
  }

  Future<void> writeFile(VsUri resource, Uint8List content) async {
    final provider = await _withWriteProvider(resource);
    try {
      FileStat? stat;
      try {
        stat = await provider.stat(resource);
      } on Object {
        // Not there yet.
      }
      if (stat != null) {
        if (stat.isDirectory) {
          throw FileOperationException(
            "Unable to write file '${_forError(resource)}' that is actually a "
            'directory',
            FileOperationResult.fileIsDirectory,
          );
        }
        _throwIfReadonly(resource, stat);
      } else {
        await _mkdirp(provider, uriDirname(resource));
      }
      await provider.writeFile(resource, content);
    } on Object catch (error) {
      throw FileOperationException(
        "Unable to write file '${_forError(resource)}' (${_describe(error)})",
        toFileOperationResult(error),
      );
    }
  }

  // --- move and copy

  Future<void> move(
    VsUri source,
    VsUri target, {
    bool overwrite = false,
  }) async {
    final sourceProvider = await _withWriteProvider(source);
    final targetProvider = await _withWriteProvider(target);
    await _moveCopy(
      sourceProvider,
      source,
      targetProvider,
      target,
      true,
      overwrite,
    );
  }

  Future<void> copy(
    VsUri source,
    VsUri target, {
    bool overwrite = false,
  }) async {
    final sourceProvider = await _withProvider(source);
    final targetProvider = await _withWriteProvider(target);
    await _moveCopy(
      sourceProvider,
      source,
      targetProvider,
      target,
      false,
      overwrite,
    );
  }

  Future<void> _moveCopy(
    FileSystemProvider sourceProvider,
    VsUri source,
    FileSystemProvider targetProvider,
    VsUri target,
    bool move,
    bool overwrite,
  ) async {
    if (source == target) return;
    final same = identical(sourceProvider, targetProvider);
    final caseSensitive = _caseSensitive(sourceProvider);
    var sameDifferentCase = false;
    if (same) {
      if (!caseSensitive) {
        sameDifferentCase = uriEqual(source, target, ignoreCase: true);
      }
      if (sameDifferentCase && !move) {
        throw StateError(
          "Unable to copy when source '${_forError(source)}' is same as target "
          "'${_forError(target)}' with different path case on a case "
          'insensitive file system',
        );
      }
      if (!sameDifferentCase &&
          uriIsEqualOrParent(target, source, ignoreCase: !caseSensitive)) {
        throw StateError(
          "Unable to move/copy when source '${_forError(source)}' is parent of "
          "target '${_forError(target)}'.",
        );
      }
    }
    final targetExists = await exists(target);
    if (targetExists && !sameDifferentCase) {
      if (!overwrite) {
        throw FileOperationException(
          "Unable to move/copy '${_forError(source)}' because target "
          "'${_forError(target)}' already exists at destination.",
          FileOperationResult.fileMoveConflict,
        );
      }
      if (same &&
          uriIsEqualOrParent(source, target, ignoreCase: !caseSensitive)) {
        throw StateError(
          "Unable to move/copy '${_forError(source)}' into "
          "'${_forError(target)}' since a file would replace the folder it is "
          'contained in.',
        );
      }
      await delete(target, recursive: true);
    }
    await _mkdirp(targetProvider, uriDirname(target));
    if (!move) {
      if (same &&
          sourceProvider.capabilities &
                  FileSystemProviderCapabilities.fileFolderCopy !=
              0) {
        await sourceProvider.copy(source, target, overwrite: overwrite);
      } else {
        await _copyAcross(sourceProvider, source, targetProvider, target);
      }
      return;
    }
    if (same) {
      await sourceProvider.rename(source, target, overwrite: overwrite);
    } else {
      await _copyAcross(sourceProvider, source, targetProvider, target);
      await delete(source, recursive: true);
    }
  }

  Future<void> _copyAcross(
    FileSystemProvider sourceProvider,
    VsUri source,
    FileSystemProvider targetProvider,
    VsUri target,
  ) async {
    final stat = await sourceProvider.stat(source);
    if (!stat.isDirectory) {
      await targetProvider.writeFile(
        target,
        await sourceProvider.readFile(source),
      );
      return;
    }
    await targetProvider.mkdir(target);
    for (final (name, _) in await sourceProvider.readdir(source)) {
      await _copyAcross(
        sourceProvider,
        uriJoin(source, name),
        targetProvider,
        uriJoin(target, name),
      );
    }
  }

  // --- folders and deleting

  Future<void> createFolder(VsUri resource) async {
    final provider = await _withWriteProvider(resource);
    await _mkdirp(provider, resource);
  }

  Future<void> _mkdirp(FileSystemProvider provider, VsUri directory) async {
    final toCreate = <String>[];
    while (directory != uriDirname(directory)) {
      try {
        final stat = await provider.stat(directory);
        if (!stat.isDirectory) {
          throw StateError(
            "Unable to create folder '${_forError(directory)}' that already "
            'exists but is not a directory',
          );
        }
        break;
      } on StateError {
        rethrow;
      } on Object catch (error) {
        if (toFileSystemProviderErrorCode(error) !=
            FileSystemProviderErrorCode.fileNotFound) {
          rethrow;
        }
        toCreate.add(uriBasename(directory));
        directory = uriDirname(directory);
      }
    }
    for (final name in toCreate.reversed) {
      directory = uriJoin(directory, name);
      try {
        await provider.mkdir(directory);
      } on Object catch (error) {
        if (toFileSystemProviderErrorCode(error) !=
            FileSystemProviderErrorCode.fileExists) {
          rethrow;
        }
      }
    }
  }

  Future<void> delete(
    VsUri resource, {
    bool recursive = false,
    bool useTrash = false,
  }) async {
    final provider = await _withWriteProvider(resource);
    if (useTrash &&
        provider.capabilities & FileSystemProviderCapabilities.trash == 0) {
      throw StateError(
        "Unable to delete file '${_forError(resource)}' via trash because "
        'provider does not support it.',
      );
    }
    FileStat? stat;
    try {
      stat = await provider.stat(resource);
    } on Object {
      // Below.
    }
    if (stat == null) {
      throw FileOperationException(
        "Unable to delete nonexistent file '${_forError(resource)}'",
        FileOperationResult.fileNotFound,
      );
    }
    _throwIfReadonly(resource, stat);
    if (!recursive && stat.isDirectory) {
      if ((await provider.readdir(resource)).isNotEmpty) {
        throw StateError(
          "Unable to delete non-empty folder '${_forError(resource)}'.",
        );
      }
    }
    await provider.delete(resource, recursive: recursive, useTrash: useTrash);
  }

  // --- watching

  /// `watch`: changes under [resource] go to [onDidFilesChange] until the
  /// returned function is called.
  void Function() watch(VsUri resource, WatchOptions options) {
    var disposed = false;
    void Function()? stop;
    unawaited(() async {
      try {
        final provider = await _withProvider(resource);
        if (disposed) return;
        stop = provider.watch(resource, options);
      } on Object {
        // Not watchable: nothing to report.
      }
    }());
    return () {
      disposed = true;
      stop?.call();
    };
  }

  /// `createWatcher`: a watch whose changes only [onChange] sees.
  void Function() createWatcher(
    VsUri resource,
    WatchOptions options,
    void Function(List<FileChange> changes) onChange,
  ) {
    var disposed = false;
    void Function()? stop;
    unawaited(() async {
      try {
        final provider = await _withProvider(resource);
        if (disposed) return;
        stop = provider.watch(resource, options, correlated: onChange);
      } on Object {
        // Not watchable.
      }
    }());
    return () {
      disposed = true;
      stop?.call();
    };
  }

  void _fire(List<FileChange> changes, FileSystemProvider provider) {
    if (changes.isEmpty || _changes.isClosed) return;
    _pending.addAll(changes);
    _flush ??= Timer(batchDelay, () {
      _flush = null;
      final batch = coalesceFileChanges([
        ..._pending,
      ], caseSensitive: _caseSensitive(provider));
      _pending.clear();
      if (batch.isNotEmpty && !_changes.isClosed) _changes.add(batch);
    });
  }

  bool _caseSensitive(FileSystemProvider provider) =>
      provider.capabilities &
          FileSystemProviderCapabilities.pathCaseSensitive !=
      0;

  void _throwIfReadonly(VsUri resource, FileStat stat) {
    if (stat.readonly) {
      throw FileOperationException(
        "Unable to modify read-only file '${_forError(resource)}'",
        FileOperationResult.filePermissionDenied,
      );
    }
  }

  @visibleForTesting
  Future<void> flushChanges() async {
    final timer = _flush;
    if (timer == null) return;
    timer.cancel();
    _flush = null;
    final batch = coalesceFileChanges([..._pending]);
    _pending.clear();
    if (batch.isNotEmpty) _changes.add(batch);
    // Let the listeners (an async stream) run.
    await Future<void>.delayed(Duration.zero);
  }

  void dispose() {
    _flush?.cancel();
    for (final s in _providerSubscriptions.values) {
      unawaited(s.cancel());
    }
    _providerSubscriptions.clear();
    _providers.clear();
    unawaited(_registrations.close());
    unawaited(_changes.close());
  }
}

/// No provider for a resource's scheme (`ENOPRO`).
final class NoFileSystemProviderException implements Exception {
  const NoFileSystemProviderException(this.resource);

  final VsUri resource;

  @override
  String toString() =>
      "ENOPRO: No file system provider found for resource '$resource'";
}

String _forError(VsUri resource) => resource.scheme == 'file'
    ? resource.fsPath()
    : resource.toString(skipEncoding: true);

String _describe(Object error) => switch (error) {
  FileOperationException(:final message) => message,
  FileSystemProviderException(:final message) => message,
  RpcRemoteError(:final message) => message,
  _ => '$error',
};

// --- URI paths (`resources.ts`, `extUri`)

/// `dirname`: the root stays the root.
VsUri uriDirname(VsUri uri) {
  final path = uri.path;
  final index = path.lastIndexOf('/');
  if (index <= 0) return uri.replace(path: '/');
  return uri.replace(path: path.substring(0, index));
}

/// `basename`.
String uriBasename(VsUri uri) {
  var path = uri.path;
  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return path.substring(path.lastIndexOf('/') + 1);
}

/// `joinPath` of one name.
VsUri uriJoin(VsUri uri, String name) => uri.joinPath([name]);

/// `extUri.isEqual`.
bool uriEqual(VsUri a, VsUri b, {bool ignoreCase = false}) {
  if (a.scheme != b.scheme || a.authority != b.authority) return false;
  String norm(String p) {
    final t = p.length > 1 && p.endsWith('/')
        ? p.substring(0, p.length - 1)
        : p;
    return ignoreCase ? t.toLowerCase() : t;
  }

  return norm(a.path) == norm(b.path);
}

/// `extUri.isEqualOrParent`: [uri] is [parent] or under it.
bool uriIsEqualOrParent(VsUri uri, VsUri parent, {bool ignoreCase = false}) {
  if (uri.scheme != parent.scheme ||
      uri.authority.toLowerCase() != parent.authority.toLowerCase()) {
    return false;
  }
  var path = uri.path;
  var base = parent.path;
  if (ignoreCase) {
    path = path.toLowerCase();
    base = base.toLowerCase();
  }
  if (path == base) return true;
  if (!base.endsWith('/')) base = '$base/';
  return path.startsWith(base);
}
