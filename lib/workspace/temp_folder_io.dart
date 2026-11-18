import 'dart:io';

import 'package:path/path.dart' as p;

/// Whether [path] is in a folder the system keeps temporary things in (or is
/// one): what an agent makes there, a clone to run another agent in say, is
/// not a project of the user's.
bool isTempFolder(String path) =>
    p.isAbsolute(path) &&
    _roots.any((root) => p.equals(root, path) || p.isWithin(root, path));

/// The system's temporary folders, as given and as Claude Code names the
/// folders in them (macOS's `/tmp` and `$TMPDIR` are links into `/private`).
final List<String> _roots = () {
  final roots = <String>{};
  void add(String path) {
    if (path.isEmpty) return;
    roots.add(p.normalize(path));
    try {
      roots.add(p.normalize(Directory(path).resolveSymbolicLinksSync()));
    } on FileSystemException {
      // Not there: as given.
    }
  }

  add(Directory.systemTemp.path);
  if (!Platform.isWindows) {
    for (final path in ['/tmp', '/var/tmp']) {
      add(path);
    }
  }
  if (Platform.isMacOS) add('/private/var/folders');
  return roots.toList();
}();
