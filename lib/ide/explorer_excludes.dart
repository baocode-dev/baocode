import 'package:path/path.dart' as p;

import 'lsp/lsp_glob.dart';

/// The files and folders the explorer leaves out, as VS Code's
/// `files.exclude` does but kept in BaoCode's own settings (`explorer.exclude`
/// in its settings.json, an array of globs): the tree shows neither them nor
/// anything under them.
///
/// A pattern with no `/` matches an entry's name anywhere (`node_modules`,
/// `*.log`); one with a `/` matches the path relative to the folder it is
/// in (`build/**`, `src/generated`).
class IdeExplorerExcludes {
  const IdeExplorerExcludes(this.patterns);

  /// The setting the patterns are kept under, in the app's settings.json.
  static const settingKey = 'explorer.exclude';

  /// None: nothing is left out.
  static const none = IdeExplorerExcludes([]);

  /// The patterns as written, in order.
  final List<String> patterns;

  bool get isEmpty => patterns.isEmpty;
  bool get isNotEmpty => patterns.isNotEmpty;

  /// The patterns in [value] (`explorer.exclude`): the non-blank strings,
  /// trimmed; none when it is not a list.
  static IdeExplorerExcludes parse(Object? value) => switch (value) {
    final List<Object?> list => IdeExplorerExcludes([
      for (final entry in list)
        if (entry is String && entry.trim().isNotEmpty) entry.trim(),
    ]),
    _ => none,
  };

  /// The value the setting is written as.
  List<String> toJson() => patterns;

  /// A copy with [pattern] added (at the end) or, where [exclude] is false,
  /// dropped; blank patterns are ignored.
  IdeExplorerExcludes withPattern(String pattern, {bool exclude = true}) {
    final trimmed = pattern.trim();
    if (trimmed.isEmpty) return this;
    final next = [...patterns];
    if (exclude) {
      if (!next.contains(trimmed)) next.add(trimmed);
    } else {
      next.remove(trimmed);
    }
    return IdeExplorerExcludes(next);
  }

  /// Whether [path] is left out of the explorer: one of [patterns] matches
  /// its name, or, where the pattern names a folder, its path relative to
  /// [root] (spelled by [paths]).
  bool hides(String path, String root, p.Context paths) {
    if (patterns.isEmpty) return false;
    final name = paths.basename(path);
    final relative = paths.relative(path, from: root).replaceAll(r'\', '/');
    for (final pattern in patterns) {
      final glob = pattern.replaceAll(r'\', '/');
      final target = glob.contains('/') ? relative : name;
      if (target.isEmpty || target == '.') continue;
      if (_matches(glob, target)) return true;
    }
    return false;
  }

  static final Map<String, LspGlob> _globs = {};

  static bool _matches(String pattern, String target) {
    if (pattern == target) return true;
    final glob = _globs.putIfAbsent(pattern, () => LspGlob(pattern));
    if (glob.matches(target)) return true;
    // `build/**` hides the folder itself too, not only what is under it (as
    // VS Code hides a folder whose every child is excluded).
    for (final suffix in const ['/**', '/*']) {
      if (!pattern.endsWith(suffix)) continue;
      final folder = pattern.substring(0, pattern.length - suffix.length);
      if (folder == target) return true;
    }
    return false;
  }

  @override
  bool operator ==(Object other) =>
      other is IdeExplorerExcludes && _same(patterns, other.patterns);

  @override
  int get hashCode => Object.hashAll(patterns);

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
