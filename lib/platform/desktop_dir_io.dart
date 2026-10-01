import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_paths.dart';

/// The user's Desktop folder, where a chat in no project works: in their
/// home, or on Windows in OneDrive where that has taken it over; null
/// without a home.
String? get desktopDirectory {
  final environment = Platform.environment;
  final home = AppPaths.home(environment);
  if (home.isEmpty) return null;
  final desktop = p.join(home, 'Desktop');
  if (Platform.isWindows && !Directory(desktop).existsSync()) {
    if (environment['OneDrive'] case final oneDrive? when oneDrive.isNotEmpty) {
      final moved = p.join(oneDrive, 'Desktop');
      if (Directory(moved).existsSync()) return moved;
    }
  }
  return desktop;
}
