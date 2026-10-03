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
