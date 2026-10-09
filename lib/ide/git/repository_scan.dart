/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The repositories of a workspace folder's subfolders, as VS Code's Git
// extension finds them (extensions/git/src/model.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971: `scanWorkspaceFolders`,
// `traverseWorkspaceFolder`), with its settings
// `git.autoRepositoryDetection`, `git.repositoryScanMaxDepth` and
// `git.repositoryScanIgnoredFolders`.
//
// Deviations: a subfolder is one when it is a working tree's top level
// (upstream opens the repository of each, a folder in the workspace
// folder's own then being that one again); `openEditors` (the repositories
// of open files) and `git.scanRepositories` are not followed; and folders
// are scanned when the workspace opens or gains them, not again when a
// repository is made in one.

import 'dart:async';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../file_service.dart';
import 'git_repository.dart';

/// How the workspace folders' subfolders are scanned for repositories.
class IdeRepositoryScan {
  const IdeRepositoryScan({
    this.subFolders = true,
    this.maxDepth = 1,
    this.ignoredFolders = const ['node_modules'],
  });

  /// settings.json's choices, upstream's defaults for those not set or
  /// not of their type.
  factory IdeRepositoryScan.parse(Map<String, Object?> settings) {
    const defaults = IdeRepositoryScan();
    return IdeRepositoryScan(
      // `true`, `subFolders`, `openEditors` or `false`.
      subFolders: switch (settings['git.autoRepositoryDetection']) {
        true || 'subFolders' => true,
        false || 'openEditors' => false,
        _ => defaults.subFolders,
      },
      maxDepth: switch (settings['git.repositoryScanMaxDepth']) {
        final int depth when depth >= -1 => depth,
        _ => defaults.maxDepth,
      },
      ignoredFolders: switch (settings['git.repositoryScanIgnoredFolders']) {
        final List<Object?> folders => folders.whereType<String>().toList(),
        _ => defaults.ignoredFolders,
      },
    );
  }

  /// Whether subfolders are scanned at all (`git.autoRepositoryDetection`
  /// `true` or `subFolders`).
  final bool subFolders;

  /// How far below the folder (`git.repositoryScanMaxDepth`): 1 for its
  /// children, -1 for no limit.
  final int maxDepth;

  /// The names of folders not looked in (`git.repositoryScanIgnoredFolders`).
  final List<String> ignoredFolders;
}

/// The repositories under [folder] [scan] finds: the subfolders, as far
/// down as it goes, that are a working tree's top level. [list] lists a
/// folder, [isRepositoryTop] asks Git about one, and [paths] spells the
/// paths of [folder]'s host.
Future<List<String>> scanRepositories(
  String folder,
  IdeRepositoryScan scan, {
  required Future<List<IdeFile>> Function(String directory) list,
  required Future<bool> Function(String folder) isRepositoryTop,
  p.Context? paths,
}) async {
  if (!scan.subFolders || scan.maxDepth == 0) return const [];
  final context = paths ?? p.context;
  final ignored = {for (final name in scan.ignoredFolders) name.toLowerCase()};
  final candidates = <String>[];
  final pending = [(path: folder, depth: 0)];
  while (pending.isNotEmpty) {
    final current = pending.removeAt(0);
    if (current.depth != 0) candidates.add(current.path);
    if (scan.maxDepth != -1 && current.depth >= scan.maxDepth) continue;
    final List<IdeFile> children;
    try {
      children = await list(current.path);
    } catch (_) {
      // Unreadable: not looked in.
      continue;
    }
    for (final child in children) {
      if (!child.isDirectory || child.name == '.git') continue;
      if (ignored.contains(child.name.toLowerCase())) continue;
      // Joined to the path asked, which a listing may spell with links
      // resolved.
      pending.add((
        path: context.join(current.path, child.name),
        depth: current.depth + 1,
      ));
    }
  }
  // Git a few at a time: each is a process (or a call to a remote host).
  final found = List<bool>.filled(candidates.length, false);
  var next = 0;
  Future<void> worker() async {
    while (next < candidates.length) {
      final index = next++;
      found[index] = await isRepositoryTop(candidates[index]);
    }
  }

  await Future.wait([
    for (var i = 0; i < math.min(8, candidates.length); i++) worker(),
  ]);
  return [
    for (var i = 0; i < candidates.length; i++)
      if (found[i]) candidates[i],
  ];
}

/// [folder]'s repositories as Source Control lists them: its own, [own]
/// (left out once known not to be one, when others were found), then
/// [found], those of its subfolders.
List<(String root, IdeGitRepository git)> ideFolderRepositories(
  String folder,
  IdeGitRepository? own,
  List<(String path, IdeGitRepository git)> found,
) => [
  if (own case final git? when found.isEmpty || !git.loaded || git.isRepository)
    (folder, git),
  ...found,
];

/// Finds the repositories of a workspace folder's subfolders, and makes
/// the repository of one found.
class IdeRepositoryDetection {
  const IdeRepositoryDetection({required this.find, required this.open});

  /// The repositories under a folder, by path.
  final Future<List<String>> Function(String folder) find;

  /// The repository at a path [find] gave.
  final IdeGitRepository Function(String path) open;
}
