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
