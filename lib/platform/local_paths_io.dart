import 'dart:io';

import 'app_paths.dart';

/// The user's home folder, where the IDE without a folder starts its
/// terminals; null without one.
String? get homeDirectory {
  final home = AppPaths.home(Platform.environment);
  return home.isEmpty ? null : home;
}

/// Whether [path] is a folder (following links), not a file or nothing.
Future<bool> isDirectory(String path) => FileSystemEntity.isDirectory(path);

/// Whether there is a file or folder at [path] (following links).
Future<bool> exists(String path) async =>
    await FileSystemEntity.type(path) != FileSystemEntityType.notFound;

/// When the file at [path] last changed; null if there is none.
Future<DateTime?> modifiedAt(String path) async {
  final stat = await FileStat.stat(path);
  return stat.type == FileSystemEntityType.notFound ? null : stat.modified;
}

/// [path]'s text, the file deleted once read (a request the `code` command
/// left for the app); null if it cannot be read.
Future<String?> takeFile(String path) async {
  try {
    final file = File(path);
    final text = await file.readAsString();
    await file.delete().catchError((Object _) => file);
    return text;
  } on FileSystemException {
    return null;
  }
}
