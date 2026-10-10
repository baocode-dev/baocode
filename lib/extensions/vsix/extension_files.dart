// An extension's files, wherever they are: inside a .vsix (under its
// `extension/` folder) or in a folder on disk (an installed extension, or
// one in development). The manifest reader and the capability analysis
// read through it.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'zip_reader.dart';

/// A file of an extension: its path relative to the extension's root
/// (`/`-separated) and its size.
class ExtensionFileInfo {
  const ExtensionFileInfo(this.path, this.size);

  final String path;
  final int size;

  @override
  String toString() => 'ExtensionFileInfo($path, $size)';
}

/// Read access to an extension's files.
abstract class ExtensionFiles {
  /// Where they are (the .vsix's path, or the folder's).
  String get location;

  /// The file at [path] (relative, `/`-separated), at most [maxBytes] of
  /// it; null when there is none.
  Future<Uint8List?> read(String path, {int? maxBytes});

  /// Every file, up to [limit] of them.
  Future<List<ExtensionFileInfo>> list({int limit = 20000});

  Future<void> close();
}

/// The files under a .vsix's `extension/` folder.
class VsixExtensionFiles implements ExtensionFiles {
  VsixExtensionFiles(this.zip, this.location);

  static const root = 'extension/';

  final ZipReader zip;
  @override
  final String location;

  @override
  Future<Uint8List?> read(String path, {int? maxBytes}) async {
    final entry = zip.entry('$root${_normalize(path)}');
    if (entry == null || entry.isDirectory) return null;
    return zip.read(entry, maxBytes: maxBytes);
  }

  @override
  Future<List<ExtensionFileInfo>> list({int limit = 20000}) async => [
    for (final entry
        in zip.entries
            .where((e) => !e.isDirectory && e.name.startsWith(root))
            .take(limit))
      ExtensionFileInfo(entry.name.substring(root.length), entry.size),
  ];

  @override
  Future<void> close() => zip.close();
}

/// The files of an extension folder on disk.
class FolderExtensionFiles implements ExtensionFiles {
  FolderExtensionFiles(this.location);

  @override
  final String location;

  @override
  Future<Uint8List?> read(String path, {int? maxBytes}) async {
    final relative = _normalize(path);
    if (relative.isEmpty || relative.split('/').contains('..')) return null;
    final file = File(p.join(location, relative));
    try {
      if (!await file.exists()) return null;
      if (maxBytes == null) return await file.readAsBytes();
      final handle = await file.open();
      try {
        return await handle.read(math.min(maxBytes, await handle.length()));
      } finally {
        await handle.close();
      }
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<List<ExtensionFileInfo>> list({int limit = 20000}) async {
    final files = <ExtensionFileInfo>[];
    final dir = Directory(location);
    try {
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final relative = p
            .relative(entity.path, from: location)
            .replaceAll('\\', '/');
        int size;
        try {
          size = await entity.length();
        } on FileSystemException {
          continue;
        }
        files.add(ExtensionFileInfo(relative, size));
        if (files.length >= limit) break;
      }
    } on FileSystemException {
      // What was listed so far.
    }
    return files;
  }

  @override
  Future<void> close() async {}
}

/// [path] without `./` and leading slashes, `/`-separated.
String _normalize(String path) {
  var normalized = p.posix.normalize(path.replaceAll('\\', '/'));
  while (normalized.startsWith('/')) {
    normalized = normalized.substring(1);
  }
  return normalized == '.' ? '' : normalized;
}
