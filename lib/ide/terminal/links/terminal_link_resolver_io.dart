import 'dart:io';

import 'terminal_link_parsing.dart';

OperatingSystem get hostOperatingSystem => Platform.isWindows
    ? OperatingSystem.windows
    : Platform.isMacOS
    ? OperatingSystem.macintosh
    : OperatingSystem.linux;

String? get hostUserHome =>
    Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];

/// Whether [path] is a folder (true), a file (false) or nothing (null),
/// following symbolic links.
Future<bool?> statPath(String path) async {
  try {
    return switch ((await FileStat.stat(path)).type) {
      FileSystemEntityType.notFound => null,
      FileSystemEntityType.directory => true,
      _ => false,
    };
  } on FileSystemException {
    return null;
  }
}
