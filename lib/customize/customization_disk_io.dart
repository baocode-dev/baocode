import 'dart:io';

import 'package:path/path.dart' as p;

import '../kernel/claude_code/claude_environment.dart';
import '../platform/local_paths_io.dart';
import 'customization_disk.dart';

CustomizationDisk? localCustomizationDisk() => const _LocalDisk();

/// This machine's files.
class _LocalDisk implements CustomizationDisk {
  const _LocalDisk();

  @override
  bool get isLocal => true;

  @override
  p.Context get paths => p.context;

  @override
  Future<String> configDir() => ClaudeEnvironment.configDir();

  @override
  Future<String?> homeDir() async => homeDirectory;

  @override
  Future<String?> read(String path) async {
    try {
      return await File(path).readAsString();
    } on Object {
      return null;
    }
  }

  @override
  Future<List<({String path, bool directory})>> children(
    String directory,
  ) async {
    try {
      return [
        await for (final entry in Directory(directory).list())
          if (entry is Directory || entry is File)
            (path: entry.path, directory: entry is Directory)
          // One the listing could not follow (a Windows junction or link
          // to a folder, as some skill managers install them): followed
          // once more; one leading nowhere as a folder, for its skill to
          // say so (see CustomizationStore).
          else if (entry is Link)
            (
              path: entry.path,
              directory:
                  await FileSystemEntity.type(entry.path) !=
                  FileSystemEntityType.file,
            ),
      ];
    } on FileSystemException {
      return const [];
    }
  }

  @override
  Future<bool?> isDirectory(String path) async =>
      switch (await FileSystemEntity.type(path)) {
        FileSystemEntityType.directory => true,
        FileSystemEntityType.file => false,
        _ => null,
      };

  @override
  Future<void> write(String path, String text) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
  }

  @override
  Future<void> delete(String path) async {
    switch (await isDirectory(path)) {
      case true:
        await Directory(path).delete(recursive: true);
      case false:
        await File(path).delete();
      // A link leading nowhere: the link.
      case null when await FileSystemEntity.isLink(path):
        await Link(path).delete();
      case null:
    }
  }
}
