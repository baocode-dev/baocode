// An in-memory `memfs` for the file service tests, like the one
// extensions register with `workspace.registerFileSystemProvider` (see
// test/fixtures/extensions/workspace-fixture).

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/files/file_service.dart';
import 'package:baocode/extensions/files/file_types.dart';

final class MemFileSystemProvider extends FileSystemProvider {
  MemFileSystemProvider({this.readonly = false, this.canCopy = true});

  final bool readonly;
  final bool canCopy;

  /// path → contents (folders have null contents).
  final entries = <String, List<int>?>{'/': null};

  int watchCalls = 0;
  final watched = <VsUri>[];
  final watchOptions = <WatchOptions>[];
  final correlated = <int, void Function(List<FileChange>)>{};
  final _stops = <void Function()>[];

  @override
  int get capabilities =>
      FileSystemProviderCapabilities.fileReadWrite |
      (canCopy ? FileSystemProviderCapabilities.fileFolderCopy : 0) |
      (readonly ? FileSystemProviderCapabilities.readonly : 0) |
      FileSystemProviderCapabilities.pathCaseSensitive |
      FileSystemProviderCapabilities.trash;

  final _changes = StreamController<List<FileChange>>.broadcast();

  @override
  Stream<List<FileChange>> get onDidChangeFile => _changes.stream;

  /// Reports changes as a watch would.
  void fire(List<FileChange> changes) => _changes.add(changes);

  /// The `$onFileSystemChange` of a *correlated* watch (no session).
  void fireCorrelated(List<FileChange> changes) {
    for (final listener in correlated.values.toList()) {
      listener(changes);
    }
  }

  void addDirectory(String path, {List<int>? contents}) =>
      entries[path] = contents;

  void addFile(String path, String contents) =>
      entries[path] = utf8.encode(contents);

  @override
  Future<FileStat> stat(VsUri resource) async {
    final path = resource.path;
    if (!entries.containsKey(path)) {
      throw FileSystemProviderException(
        'ENOENT: $path',
        FileSystemProviderErrorCode.fileNotFound,
      );
    }
    final directory = entries[path] == null;
    return FileStat(
      type: directory ? FileType.directory : FileType.file,
      mtime: 1,
      size: entries[path]?.length ?? 0,
      permissions: readonly ? FilePermission.readonly : null,
    );
  }

  @override
  Future<List<(String, int)>> readdir(VsUri resource) async {
    final prefix = resource.path == '/' ? '/' : '${resource.path}/';
    final names = <String, int>{};
    for (final MapEntry(:key, :value) in entries.entries) {
      if (key == resource.path || !key.startsWith(prefix)) continue;
      final rest = key.substring(prefix.length);
      if (rest.isEmpty) continue;
      final name = rest.split('/').first;
      names[name] = rest.contains('/') || value == null
          ? FileType.directory
          : FileType.file;
    }
    return [for (final MapEntry(:key, :value) in names.entries) (key, value)];
  }

  @override
  Future<Uint8List> readFile(VsUri resource) async {
    final contents = entries[resource.path];
    if (contents == null) {
      throw FileSystemProviderException(
        'ENOENT: ${resource.path}',
        FileSystemProviderErrorCode.fileNotFound,
      );
    }
    return Uint8List.fromList(contents);
  }

  @override
  Future<void> writeFile(
    VsUri resource,
    Uint8List content, {
    bool create = true,
    bool overwrite = true,
  }) async {
    final exists = entries.containsKey(resource.path);
    if (exists && !overwrite) {
      throw const FileSystemProviderException(
        'EEXIST',
        FileSystemProviderErrorCode.fileExists,
      );
    }
    if (!exists && !create) {
      throw const FileSystemProviderException(
        'ENOENT',
        FileSystemProviderErrorCode.fileNotFound,
      );
    }
    entries[resource.path] = content.toList();
  }

  @override
  Future<void> mkdir(VsUri resource) async {
    if (entries.containsKey(resource.path)) {
      throw const FileSystemProviderException(
        'EEXIST',
        FileSystemProviderErrorCode.fileExists,
      );
    }
    entries[resource.path] = null;
  }

  @override
  Future<void> delete(
    VsUri resource, {
    bool recursive = false,
    bool useTrash = false,
  }) async {
    if (!entries.containsKey(resource.path)) {
      throw const FileSystemProviderException(
        'ENOENT',
        FileSystemProviderErrorCode.fileNotFound,
      );
    }
    entries.removeWhere(
      (key, _) => key == resource.path || key.startsWith('${resource.path}/'),
    );
    if (useTrash) trashed.add(resource.path);
  }

  final trashed = <String>[];

  @override
  Future<void> rename(VsUri from, VsUri to, {bool overwrite = false}) async {
    if (entries.containsKey(to.path) && !overwrite) {
      throw const FileSystemProviderException(
        'EEXIST',
        FileSystemProviderErrorCode.fileExists,
      );
    }
    _move(from.path, to.path);
  }

  void _move(String from, String to) {
    final moved = <String, List<int>?>{};
    entries.removeWhere((key, value) {
      if (key == from || key.startsWith('$from/')) {
        moved[to + key.substring(from.length)] = value;
        return true;
      }
      return false;
    });
    entries.addAll(moved);
  }

  @override
  Future<void> copy(VsUri from, VsUri to, {bool overwrite = false}) async {
    if (!canCopy) throw UnsupportedError('copy');
    final copied = <String, List<int>?>{};
    var found = false;
    for (final MapEntry(:key, :value) in entries.entries) {
      if (key == from.path || key.startsWith('${from.path}/')) {
        found = true;
        copied[to.path + key.substring(from.path.length)] = value == null
            ? null
            : [...value];
      }
    }
    if (!found) {
      throw const FileSystemProviderException(
        'ENOENT',
        FileSystemProviderErrorCode.fileNotFound,
      );
    }
    entries.addAll(copied);
  }

  @override
  void Function() watch(
    VsUri resource,
    WatchOptions options, {
    void Function(List<FileChange> changes)? correlated,
  }) {
    watchCalls++;
    watched.add(resource);
    watchOptions.add(options);
    final session = watchCalls;
    if (correlated != null) this.correlated[session] = correlated;
    void stop() {
      this.correlated.remove(session);
      _stops.remove(stop);
    }

    _stops.add(stop);
    return stop;
  }

  bool get watching => _stops.isNotEmpty;

  void dispose() => unawaited(_changes.close());
}
