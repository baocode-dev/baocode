import 'dart:typed_data';

import 'icon_storage_stub.dart'
    if (dart.library.io) 'icon_storage_io.dart'
    as platform;

/// Where the [IconLibrary]'s pictures are kept: files in a folder, listed
/// by `index.json`.
abstract interface class IconStorage {
  /// The data folder's `icons` (none on the web), or [path].
  factory IconStorage.directory([String? path]) = platform.DirectoryIconStorage;

  /// What `index.json` lists; empty the first time, or when it cannot be
  /// read.
  Future<List<Object?>> readIndex();

  Future<void> writeIndex(List<Object?> index);

  /// The file [name]; null when it is not there.
  Future<Uint8List?> read(String name);

  Future<void> write(String name, Uint8List bytes);

  Future<void> delete(String name);

  /// The size of the file at [path] the user gave (picked, dropped or
  /// pasted); null when there is none.
  Future<int?> userFileSize(String path);

  /// The file at [path] the user gave; null when it cannot be read.
  Future<Uint8List?> readUserFile(String path);
}

/// Kept only while it lives, e.g. under test; [userFiles] are the files
/// the user may give.
class MemoryIconStorage implements IconStorage {
  MemoryIconStorage({Map<String, Uint8List>? userFiles})
    : userFiles = {...?userFiles};

  List<Object?> index = const [];
  final Map<String, Uint8List> files = {};
  final Map<String, Uint8List> userFiles;

  @override
  Future<List<Object?>> readIndex() async => index;

  @override
  Future<void> writeIndex(List<Object?> index) async => this.index = index;

  @override
  Future<Uint8List?> read(String name) async => files[name];

  @override
  Future<void> write(String name, Uint8List bytes) async => files[name] = bytes;

  @override
  Future<void> delete(String name) async => files.remove(name);

  @override
  Future<int?> userFileSize(String path) async => userFiles[path]?.length;

  @override
  Future<Uint8List?> readUserFile(String path) async => userFiles[path];
}
