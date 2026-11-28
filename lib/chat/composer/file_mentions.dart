import 'dart:async';

import 'package:path/path.dart' as p;

import '../../ide/file_service.dart';
import '../../ide/ide_quick_open.dart';
import '../../kernel/kernel_types.dart';
import 'composer_embeds.dart' show fileSuggestion;
import 'composer_mock_data.dart';

/// Where an `@` looks files up: the project's listing (an [IdeFileIndex],
/// the search palette's, listed once and kept), which covers each folder of
/// a multi-folder workspace where the kernel sees its own folder alone; any
/// file by a path from a root (`/…`, `~/…`, `C:\…`), on the project's host;
/// and the kernel's own suggestions (folders among them).
class FileMentions {
  FileMentions({
    required this.files,
    required this.paths,
    required this.index,
    this.home,
  });

  /// The project's host's files.
  final IdeFileService files;

  /// How its host spells paths.
  final p.Context paths;

  /// The project's listing.
  final IdeFileIndex index;

  /// What `~` stands for; null while unknown (e.g. a remote host not yet
  /// connected).
  final String? Function()? home;

  static const _limit = 50;

  /// Listed again past this, as the next `@` is typed.
  static const _maxAge = Duration(minutes: 1);
  DateTime? _listedAt;

  /// The kernel's answer is waited for this long once the listing's is in.
  static const _kernelWait = Duration(milliseconds: 800);

  /// Files and folders for [query] (what follows the `@`), tags of them
  /// referring to them from [root] (the conversation's directory) when in
  /// it, else by their absolute paths; [kernel] the kernel's lookup.
  Future<List<Suggestion>> suggest(
    String query, {
    String? root,
    Future<List<FileSuggestion>> Function(String query)? kernel,
  }) async {
    if (_directDirectory(query, root) case final direct?) {
      return await _inDirectory(direct.directory, direct.prefix, query, root) ??
          const [];
    }
    if (_relativeDirectory(query, root) case final dir?) {
      if (await _inDirectory(dir, '', query, root) case final entries?) {
        return entries;
      }
    }
    final asked = _safely(
      Future(() => kernel?.call(query) ?? const <FileSuggestion>[]),
    );
    final now = DateTime.now();
    final listedAt = _listedAt;
    if (!index.loaded ||
        query.isEmpty ||
        listedAt == null ||
        now.difference(listedAt) > _maxAge) {
      _listedAt = now;
      unawaited(index.refresh());
    }
    if (!index.loaded) {
      // The first listing of a large project takes a while: the kernel's
      // answer meanwhile, unless it has none.
      final kernelFiles = await asked;
      if (kernelFiles.isNotEmpty) return [..._kernelSuggestions(kernelFiles)];
      await index.refresh();
    }
    final kernelFiles = await asked.timeout(
      _kernelWait,
      onTimeout: () => const [],
    );
    final merged = await _merge(query, root, kernelFiles);
    if (merged.isNotEmpty) return merged;
    if (_relativePrefix(query, root) case final rel?) {
      if (await _inDirectory(rel.directory, rel.prefix, query, root)
          case final entries?) {
        return entries;
      }
    }
    return merged;
  }

  /// The listing's matches, then the kernel's not among them.
  Future<List<Suggestion>> _merge(
    String query,
    String? root,
    List<FileSuggestion> kernelFiles,
  ) async {
    final filter = query.replaceAll(r'\', '/');
    final seen = <String>{};
    final suggestions = <Suggestion>[];
    if (filter.isEmpty) {
      // A workspace's folders, which the kernel's directory is none of.
      for (final folder in index.roots ?? const <String>[]) {
        final reference = _reference(folder, root);
        if (!seen.add(_key(reference))) continue;
        suggestions.add(
          Suggestion(
            kind: SuggestionKind.folder,
            label: paths.basename(folder),
            path: reference,
          ),
        );
      }
    } else {
      // The files matching, and the folders whose names match, best first;
      // a folder first of the two where they match as well.
      final (files, folders) = await (
        index.find(filter, limit: _limit),
        index.findFolders(filter, limit: _maxFolders, minScore: _nameMatch),
      ).wait;
      final ranked = <({String path, String relative, int score, bool folder})>[
        for (final (:path, :relative) in files)
          (
            path: path,
            relative: relative,
            score: scoreFilePath(filter, relative)?.score ?? 0,
            folder: false,
          ),
        for (final (folder: (:path, :relative), :score) in folders)
          (path: path, relative: relative, score: score, folder: true),
      ];
      ranked.sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        if (a.folder != b.folder) return a.folder ? -1 : 1;
        return a.relative.length.compareTo(b.relative.length);
      });
      for (final (:path, :relative, score: _, :folder) in ranked) {
        if (suggestions.length >= _limit) break;
        final reference = _reference(path, root);
        if (!seen.add(_key(reference))) continue;
        final slash = relative.lastIndexOf('/');
        suggestions.add(
          Suggestion(
            kind: folder ? SuggestionKind.folder : SuggestionKind.file,
            label: relative.substring(slash + 1),
            detail: slash < 0 ? '' : relative.substring(0, slash),
            path: reference,
          ),
        );
      }
    }
    for (final suggestion in _kernelSuggestions(kernelFiles)) {
      if (suggestions.length >= _limit) break;
      if (seen.add(_key(suggestion.value))) suggestions.add(suggestion);
    }
    return suggestions;
  }

  /// At most this many folders among the files.
  static const _maxFolders = 10;

  /// What [scoreFilePath] gives a match of the name, not only of the path.
  static const _nameMatch = 1000;

  Iterable<Suggestion> _kernelSuggestions(List<FileSuggestion> files) =>
      files.map(fileSuggestion);

  /// [path] as a tag refers to it: from [root] when in it.
  String _reference(String path, String? root) =>
      root != null && paths.isWithin(root, path)
      ? paths.relative(path, from: root)
      : path;

  static String _key(String path) {
    var key = path.replaceAll(r'\', '/');
    if (key.endsWith('/')) key = key.substring(0, key.length - 1);
    return key;
  }

  bool _isSeparator(String char) =>
      char == '/' || (paths.style == p.Style.windows && char == r'\');

  int _lastSeparator(String query) => paths.style == p.Style.windows
      ? query.lastIndexOf(RegExp(r'[\\/]'))
      : query.lastIndexOf('/');

  bool _isRooted(String query) {
    final windows = paths.style == p.Style.windows;
    return (!windows && query.startsWith('/')) ||
        query.startsWith('~/') ||
        (windows && query.startsWith(r'~\')) ||
        (windows && RegExp(r'^[A-Za-z]:[\\/]').hasMatch(query));
  }

  /// [query] as an explicit directory path (`/…`, `~/…`, `C:\…`, `./…`,
  /// `../…`): the resolved folder and the name prefix typed after it; null
  /// for a regular project query.
  ({String directory, String prefix})? _directDirectory(
    String query,
    String? root,
  ) {
    if (_isRooted(query)) {
      final cut = _lastSeparator(query);
      var directory = query.substring(0, cut + 1);
      if (directory.startsWith('~')) {
        final home = this.home?.call();
        if (home == null || home.isEmpty) return null;
        directory = paths.join(home, directory.substring(2));
      }
      return (directory: directory, prefix: query.substring(cut + 1));
    }
    if (root == null) return null;
    final windows = paths.style == p.Style.windows;
    final dotRelative =
        query.startsWith('./') ||
        query.startsWith('../') ||
        (windows && (query.startsWith(r'.\') || query.startsWith(r'..\')));
    if (!dotRelative) return null;
    final cut = _lastSeparator(query);
    final directory = paths.normalize(
      paths.join(root, query.substring(0, cut + 1)),
    );
    return (directory: directory, prefix: query.substring(cut + 1));
  }

  /// A relative folder path ending in a separator (e.g. `lib/chat/`), resolved
  /// from [root], to list its direct entries when browsing folders.
  String? _relativeDirectory(String query, String? root) {
    if (root == null || query.isEmpty || _isRooted(query)) return null;
    if (!_isSeparator(query[query.length - 1])) return null;
    return paths.normalize(paths.join(root, query));
  }

  /// A relative `dir/prefix` path resolved from [root], used as a fallback
  /// when the project index finds nothing (e.g. hidden or unindexed files).
  ({String directory, String prefix})? _relativePrefix(
    String query,
    String? root,
  ) {
    if (root == null || query.isEmpty || _isRooted(query)) return null;
    final cut = _lastSeparator(query);
    if (cut <= 0 || cut == query.length - 1) return null;
    return (
      directory: paths.normalize(paths.join(root, query.substring(0, cut + 1))),
      prefix: query.substring(cut + 1),
    );
  }

  /// The entries of [directory] whose names match [prefix], those starting
  /// with it first; hidden ones only when [prefix] starts with a dot. Returns
  /// null if [directory] cannot be listed.
  Future<List<Suggestion>?> _inDirectory(
    String directory,
    String prefix,
    String query,
    String? root,
  ) async {
    List<IdeFile> entries;
    try {
      entries = await files.list(directory);
    } on Object {
      return null;
    }
    final lower = prefix.toLowerCase();
    final hidden = prefix.startsWith('.');
    final ranked = <({IdeFile entry, int score})>[];
    for (final entry in entries) {
      if (!hidden && entry.name.startsWith('.')) continue;
      final name = entry.name.toLowerCase();
      final score = name.startsWith(lower)
          ? 2
          : fuzzyMatch(entry.name, prefix) != null
          ? 1
          : 0;
      if (score > 0) ranked.add((entry: entry, score: score));
    }
    ranked.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      // Folders first, as a listing shows them.
      if (a.entry.isDirectory != b.entry.isDirectory) {
        return a.entry.isDirectory ? -1 : 1;
      }
      return a.entry.name.toLowerCase().compareTo(b.entry.name.toLowerCase());
    });
    // Where it is as typed (`~/Documents`), its trailing separator off.
    final shown = query.substring(0, query.length - prefix.length);
    final trimmed = shown.substring(0, shown.length - 1);
    final detail = trimmed.isEmpty || trimmed.endsWith(':') ? shown : trimmed;
    return [
      for (final (:entry, score: _) in ranked.take(_limit))
        Suggestion(
          kind: entry.isDirectory ? SuggestionKind.folder : SuggestionKind.file,
          label: entry.name,
          detail: detail,
          path: _reference(paths.join(directory, entry.name), root),
        ),
    ];
  }

  static Future<List<FileSuggestion>> _safely(
    Future<List<FileSuggestion>> asked,
  ) async {
    try {
      return await asked;
    } on Object {
      return const [];
    }
  }
}
