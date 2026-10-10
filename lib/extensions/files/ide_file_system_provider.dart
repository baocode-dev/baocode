// The `file` scheme of a remote project: its host's files, through the
// workspace's IdeFileService (whose paths are the host's).
//
// What the IDE's file service cannot do is approximated: a stat lists the
// parent folder, writing goes through the text API (bytes as UTF-8, a new
// file through `writeBytes`), and only flat watches are possible (the
// host watches one folder at a time); recursive ones report nothing.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:path/path.dart' as p;

import '../../ide/file_service.dart';
import 'file_service.dart';
import 'file_types.dart';

final class IdeFileSystemProvider extends FileSystemProvider {
  IdeFileSystemProvider(this.files);

  final IdeFileService files;

  @override
  int get capabilities =>
      FileSystemProviderCapabilities.fileReadWrite |
      FileSystemProviderCapabilities.fileFolderCopy |
      FileSystemProviderCapabilities.pathCaseSensitive;

  final _changes = StreamController<List<FileChange>>.broadcast();

  @override
  Stream<List<FileChange>> get onDidChangeFile => _changes.stream;

  static String _path(VsUri resource) => resource.path;

  static Never _rethrow(Object error, String path) {
    if (error is FileSystemProviderException) throw error;
    throw switch (error) {
      IdeFileNotFoundException() => FileSystemProviderException(
        'ENOENT: $path',
        FileSystemProviderErrorCode.fileNotFound,
      ),
      IdeFileExistsException() => FileSystemProviderException(
        'EEXIST: $path',
        FileSystemProviderErrorCode.fileExists,
      ),
      _ => FileSystemProviderException(
        '$error',
        FileSystemProviderErrorCode.unknown,
      ),
    };
  }

  Future<IdeFile?> _entry(String path) async {
    final parent = p.posix.dirname(path);
    final name = p.posix.basename(path);
    try {
      for (final entry in await files.list(parent)) {
        if (entry.name == name) return entry;
      }
    } on Object {
      return null;
    }
    return null;
  }

  @override
  Future<FileStat> stat(VsUri resource) async {
    final path = _path(resource);
    if (path == '/') return const FileStat(type: FileType.directory);
    final entry = await _entry(path);
    if (entry == null) {
      throw FileSystemProviderException(
        'ENOENT: $path',
        FileSystemProviderErrorCode.fileNotFound,
      );
    }
    return FileStat(
      type: entry.isDirectory ? FileType.directory : FileType.file,
    );
  }

  @override
  Future<List<(String, int)>> readdir(VsUri resource) async {
    try {
      return [
        for (final entry in await files.list(_path(resource)))
          (entry.name, entry.isDirectory ? FileType.directory : FileType.file),
      ];
    } on Object catch (e) {
      _rethrow(e, _path(resource));
    }
  }

  @override
  Future<Uint8List> readFile(VsUri resource) async {
    final path = _path(resource);
    try {
      if (files case final IdeHostFiles host) return await host.readBytes(path);
      return utf8.encode(await files.read(path, force: true));
    } on Object catch (e) {
      _rethrow(e, path);
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
    final existing = await _entry(path);
    if (existing != null && !overwrite) {
      throw FileSystemProviderException(
        'EEXIST: $path',
        FileSystemProviderErrorCode.fileExists,
      );
    }
    if (existing == null && !create) {
      throw FileSystemProviderException(
        'ENOENT: $path',
        FileSystemProviderErrorCode.fileNotFound,
      );
    }
    try {
      if (existing == null) {
        await files.writeBytes(path, content);
        return;
      }
      await files.read(path, force: true);
      await files.write(path, utf8.decode(content, allowMalformed: true));
    } on Object catch (e) {
      _rethrow(e, path);
    }
  }

  @override
  Future<void> mkdir(VsUri resource) async {
    try {
      await files.create(_path(resource), directory: true);
    } on Object catch (e) {
      _rethrow(e, _path(resource));
    }
  }

  @override
  Future<void> delete(
    VsUri resource, {
    bool recursive = false,
    bool useTrash = false,
  }) async {
    try {
      await files.delete(_path(resource));
    } on Object catch (e) {
      _rethrow(e, _path(resource));
    }
  }

  @override
  Future<void> rename(VsUri from, VsUri to, {bool overwrite = false}) async {
    try {
      if (overwrite && await _entry(_path(to)) != null) {
        await files.delete(_path(to));
      }
      await files.rename(_path(from), _path(to));
    } on Object catch (e) {
      _rethrow(e, _path(from));
    }
  }

  @override
  Future<void> copy(VsUri from, VsUri to, {bool overwrite = false}) async {
    try {
      if (overwrite && await _entry(_path(to)) != null) {
        await files.delete(_path(to));
      }
      await files.copy(_path(from), _path(to));
    } on Object catch (e) {
      _rethrow(e, _path(from));
    }
  }

  @override
  void Function() watch(
    VsUri resource,
    WatchOptions options, {
    void Function(List<FileChange> changes)? correlated,
  }) {
    final host = files;
    if (options.recursive || host is! IdeHostFiles) return () {};
    // The host says a folder changed, not what: report the folder.
    final subscription = host.watchDirectory(_path(resource)).listen((_) {
      final change = [FileChange(resource, FileChangeType.updated)];
      if (correlated != null) {
        correlated(change);
      } else if (!_changes.isClosed) {
        _changes.add(change);
      }
    }, onError: (Object _) {});
    return () => unawaited(subscription.cancel());
  }

  void dispose() => unawaited(_changes.close());
}
