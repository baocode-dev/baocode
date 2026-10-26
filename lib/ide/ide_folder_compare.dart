// JetBrains IDEs' Compare Directories: the files two folders differ in,
// one's only, the other's only, or in both with other contents.

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'file_service.dart';

enum IdeFolderChange { added, deleted, modified }

/// A file two folders differ in: [path] from the folders, `/` between its
/// parts; [IdeFolderChange.added] for the second's only.
typedef IdeFolderDifference = ({String path, IdeFolderChange change});

/// The files [original] and [modified] differ in, by their paths, as far
/// as [limit] files each.
Future<List<IdeFolderDifference>> ideCompareFolders(
  IdeFileService files,
  String original,
  String modified, {
  int limit = 5000,
}) async {
  Future<Set<String>> list(String folder) async {
    final listing = await listProjectFiles(files, folder, limit: limit);
    return {
      for (final path in listing.paths)
        p.posix.joinAll(p.split(p.relative(path, from: folder))),
    };
  }

  final (before, after) = await (list(original), list(modified)).wait;
  Future<bool> same(String path) async {
    try {
      final (a, b) = await (
        readBytesThrough(files, p.joinAll([original, ...path.split('/')])),
        readBytesThrough(files, p.joinAll([modified, ...path.split('/')])),
      ).wait;
      return listEquals(a, b);
    } catch (_) {
      return false;
    }
  }

  final differences = <IdeFolderDifference>[
    for (final path in before.difference(after))
      (path: path, change: IdeFolderChange.deleted),
    for (final path in after.difference(before))
      (path: path, change: IdeFolderChange.added),
  ];
  for (final path in before.intersection(after)) {
    if (!await same(path)) {
      differences.add((path: path, change: IdeFolderChange.modified));
    }
  }
  return differences..sort((a, b) => a.path.compareTo(b.path));
}
