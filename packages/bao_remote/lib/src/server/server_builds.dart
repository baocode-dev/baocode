import 'dart:io';

import 'package:path/path.dart' as p;

const defaultServerBuildsKeep = 3;

/// Prunes sibling builds only when [executable] is in a server install.
void pruneServerBuildsForExecutable(
  String executable, {
  int keep = defaultServerBuildsKeep,
}) {
  final currentDir = File(executable).parent;
  final root = currentDir.parent;
  if (p.basename(root.path) != '.baocode-server') return;
  pruneServerBuilds(root: root, currentDir: currentDir, keep: keep);
}

/// Keeps the running build and fills the remaining slots with the newest binaries.
void pruneServerBuilds({
  required Directory root,
  required Directory currentDir,
  int keep = defaultServerBuildsKeep,
  void Function(Directory dir)? delete,
}) {
  delete ??= (dir) => dir.deleteSync(recursive: true);
  try {
    final builds = <({Directory dir, DateTime modified})>[];
    for (final entry in root.listSync(followLinks: false)) {
      if (entry is! Directory || p.equals(entry.path, currentDir.path)) {
        continue;
      }
      final name = p.basename(entry.path);
      if (name == 'data' || name == 'run') continue;
      for (final binary in ['baocode-server', 'baocode-server.exe']) {
        final path = p.join(entry.path, binary);
        if (FileSystemEntity.typeSync(path, followLinks: false) !=
            FileSystemEntityType.file) {
          continue;
        }
        final stat = File(path).statSync();
        if (stat.type != FileSystemEntityType.file) continue;
        builds.add((dir: entry, modified: stat.modified));
        break;
      }
    }
    builds.sort((a, b) {
      final byTime = b.modified.compareTo(a.modified);
      return byTime != 0
          ? byTime
          : p.basename(b.dir.path).compareTo(p.basename(a.dir.path));
    });
    for (final build in builds.skip(keep > 1 ? keep - 1 : 0)) {
      try {
        delete(build.dir);
      } on FileSystemException {
        // Still running or already removed by another server.
      }
    }
  } on FileSystemException {
    // Cleanup can wait until the next start.
  }
}
