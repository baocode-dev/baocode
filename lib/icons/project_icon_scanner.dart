import 'dart:io';

import 'package:path/path.dart' as p;

/// A picture file in a project that may be its icon: where it is, as a
/// path relative to the project's root, and how likely one it is.
typedef ProjectIconCandidate = ({String path, int score});

/// The picture files in a project's folder that may be its icon, best
/// first: shallowly looked for by name (a logo, an icon, a favicon) and
/// ranked, not read — [IconLibrary.previewFile] shows one, its
/// [IconImage.id] the id it would have once kept.
///
/// The files a project holds by name, the depth they are found at, and a
/// couple per folder: enough for a favicon.ico at its root, a logo.png in
/// its assets, an iOS AppIcon or an Android mipmap, without walking a
/// node_modules or a build.
class ProjectIconScanner {
  /// How many candidates [scan] answers with, at most.
  static const maxCandidates = 6;

  /// The extensions a candidate has: what [IconLibrary] reads (no .icns,
  /// which it does not).
  static const extensions = {'png', 'jpg', 'jpeg', 'webp', 'gif', 'svg', 'ico'};

  /// How deep into the project's folder a file may be: enough for
  /// ios/Runner/Assets.xcassets/AppIcon.appiconset, no further.
  static const depth = 4;

  /// The folders not looked into (their names, anywhere).
  static const _skipped = {
    '.git',
    '.hg',
    '.svn',
    '.dart_tool',
    '.gradle',
    '.idea',
    '.vscode',
    'node_modules',
    'build',
    'dist',
    'out',
    'vendor',
    'target',
    'pods',
    'coverage',
    'test',
    'tests',
    '__tests__',
    'example',
    'examples',
    'docs',
  };

  /// How many candidates one folder answers with, at most: an
  /// AppIcon.appiconset holds a picture per size, all the same icon.
  static const _perDirectory = 2;

  /// Looks for candidates in [root], best first (their absolute paths);
  /// none when there is no such folder.
  static Future<List<String>> scan(String root) async {
    final directory = Directory(root);
    if (!await directory.exists()) return const [];
    final found = <ProjectIconCandidate>[];
    await _walk(root, directory, 0, found);
    return [
      for (final candidate in _best(found)) p.join(root, candidate.path),
    ];
  }

  static Future<void> _walk(
    String root,
    Directory directory,
    int depth,
    List<ProjectIconCandidate> found,
  ) async {
    final List<FileSystemEntity> entries;
    try {
      entries = await directory.list(followLinks: false).toList();
    } on FileSystemException {
      return;
    }
    for (final entry in entries) {
      final name = p.basename(entry.path);
      if (entry is Link) continue;
      if (entry is Directory) {
        if (depth >= ProjectIconScanner.depth) continue;
        if (_skipped.contains(name.toLowerCase())) continue;
        await _walk(root, entry, depth + 1, found);
        continue;
      }
      if (entry is! File) continue;
      if (!extensions.contains(p.extension(name).substring(1).toLowerCase())) {
        continue;
      }
      // The path as ranked: relative, on / separators.
      final relative = p.posix
          .normalize(entry.path.substring(root.length + 1))
          .replaceAll('\\', '/');
      if (_score(relative) case final score when score > 0) {
        found.add((path: relative, score: score));
      }
    }
  }

  /// [paths] (each relative to the project's root, on / separators)
  /// scored and sorted, best first: what [scan] walks, as pure logic.
  static List<ProjectIconCandidate> rank(Iterable<String> paths) {
    final candidates = [
      for (final path in paths)
        if (_score(path) case final score when score > 0)
          (path: path, score: score),
    ];
    return _best(candidates);
  }

  /// How likely [path] (relative, on / separators) is an icon; 0 for one
  /// not a candidate at all.
  static int _score(String path) {
    final stem = p.posix.basenameWithoutExtension(path).toLowerCase();
    final depth = '/'.allMatches(path).length;
    var score = 0;
    if (stem == 'logo') {
      score = 100;
    } else if (stem.startsWith('logo')) {
      score = 90;
    } else if (stem == 'icon' || stem == 'appicon') {
      score = 85;
    } else if (stem.startsWith('icon') || stem.startsWith('appicon')) {
      score = 75;
    } else if (stem.startsWith('ic_launcher')) {
      // An Android app's launcher icon, mipmap per density.
      score = 75;
    } else if (stem.contains('logo')) {
      score = 60;
    } else if (stem.contains('icon')) {
      score = 40;
    } else {
      return 0;
    }
    if (depth == 0) score += 15;
    score += (ProjectIconScanner.depth - depth) * 5;
    return score;
  }

  /// The best of [candidates]: a couple per folder (the same picture per
  /// size counts once), then [maxCandidates] by score, ties by path.
  static List<ProjectIconCandidate> _best(
    List<ProjectIconCandidate> candidates,
  ) {
    int byScore(ProjectIconCandidate a, ProjectIconCandidate b) {
      final scores = b.score.compareTo(a.score);
      return scores != 0 ? scores : a.path.compareTo(b.path);
    }

    candidates.sort(byScore);
    // The same picture per size or density, in a folder each or named by
    // its size, counts once: the best-scored of its name.
    final names = <String>{};
    candidates = [
      for (final candidate in candidates)
        if (names.add(p.posix.basename(candidate.path))) candidate,
    ];
    final perDirectory = <String, int>{};
    final best = <ProjectIconCandidate>[];
    for (final candidate in candidates) {
      final directory = p.posix.dirname(candidate.path);
      final taken = perDirectory[directory] ?? 0;
      if (taken >= _perDirectory) continue;
      perDirectory[directory] = taken + 1;
      best.add(candidate);
      if (best.length == maxCandidates) break;
    }
    return best;
  }
}
