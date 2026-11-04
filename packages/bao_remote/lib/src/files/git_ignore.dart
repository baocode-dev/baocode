import 'dart:io';

import 'package:path/path.dart' as p;

/// The rules of one ignore file (`.gitignore`, `.git/info/exclude`), as
/// gitignore(5) reads them: the last matching rule decides, `!` re-includes,
/// a trailing `/` matches only folders, and a `/` elsewhere anchors the rule
/// to the file's folder.
class GitIgnore {
  GitIgnore.parse(String text) : _rules = _parse(text);

  final List<_Rule> _rules;

  bool get isEmpty => _rules.isEmpty;

  /// Whether a rule matches paths, not just names.
  late final bool isAnchored = _rules.any((rule) => rule.anchored);

  /// Whether the rules ignore [path] (relative to the file's folder, with
  /// `/`; its last segment [name]): true, false for one re-included, null
  /// where no rule matches.
  bool? decide(String path, String name, {required bool isDirectory}) {
    for (var i = _rules.length - 1; i >= 0; i--) {
      final rule = _rules[i];
      if (rule.directoryOnly && !isDirectory) continue;
      if (rule.matches(path, name)) return !rule.negated;
    }
    return null;
  }

  static List<_Rule> _parse(String text) => [
    for (final line in text.split('\n'))
      ?_Rule.parse(line),
  ];
}

class _Rule {
  _Rule({
    required this.negated,
    required this.directoryOnly,
    required this.anchored,
    this.literal,
    this.suffix,
    this.regExp,
  });

  final bool negated;
  final bool directoryOnly;

  /// Matched against the path from the ignore file's folder, not the name.
  final bool anchored;

  // The common rules (`build`, `*.log`) compare strings; others match a
  // regular expression.
  final String? literal;
  final String? suffix;
  final RegExp? regExp;

  bool matches(String path, String name) {
    final subject = anchored ? path : name;
    if (literal case final literal?) return subject == literal;
    if (suffix case final suffix?) return subject.endsWith(suffix);
    return regExp!.hasMatch(subject);
  }

  static _Rule? parse(String line) {
    if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
    // Trailing spaces, unless escaped.
    var end = line.length;
    while (end > 0 && line.codeUnitAt(end - 1) == 0x20) {
      if (end > 1 && line.codeUnitAt(end - 2) == 0x5C) break;
      end--;
    }
    var pattern = line.substring(0, end);
    if (pattern.isEmpty || pattern.startsWith('#')) return null;
    final negated = pattern.startsWith('!');
    if (negated) pattern = pattern.substring(1);
    final directoryOnly = pattern.endsWith('/');
    if (directoryOnly) pattern = pattern.substring(0, pattern.length - 1);
    final anchored = pattern.contains('/');
    if (pattern.startsWith('/')) pattern = pattern.substring(1);
    if (pattern.isEmpty) return null;
    if (!pattern.contains(_wildcards)) {
      return _Rule(
        negated: negated,
        directoryOnly: directoryOnly,
        anchored: anchored,
        literal: pattern,
      );
    }
    if (!anchored &&
        pattern.startsWith('*') &&
        !pattern.substring(1).contains(_wildcards)) {
      return _Rule(
        negated: negated,
        directoryOnly: directoryOnly,
        anchored: false,
        suffix: pattern.substring(1),
      );
    }
    return _Rule(
      negated: negated,
      directoryOnly: directoryOnly,
      anchored: anchored,
      regExp: RegExp(_regExpSource(pattern)),
    );
  }

  static final _wildcards = RegExp(r'[*?[\\]');

  static String _regExpSource(String glob) {
    final out = StringBuffer('^');
    var i = 0;
    while (i < glob.length) {
      final atSegment = i == 0 || glob[i - 1] == '/';
      if (atSegment && glob.startsWith('**/', i)) {
        out.write('(?:.*/)?');
        i += 3;
        continue;
      }
      if (atSegment && i == glob.length - 2 && glob.startsWith('**', i)) {
        out.write('.*');
        break;
      }
      final char = glob[i];
      switch (char) {
        case '*':
          while (i + 1 < glob.length && glob[i + 1] == '*') {
            i++;
          }
          out.write('[^/]*');
        case '?':
          out.write('[^/]');
        case r'\' when i + 1 < glob.length:
          i++;
          out.write(RegExp.escape(glob[i]));
        case '[':
          final close = _classEnd(glob, i);
          if (close == null) {
            out.write(r'\[');
          } else {
            var body = glob.substring(i + 1, close);
            final negate = body.startsWith('!') || body.startsWith('^');
            if (negate) body = body.substring(1);
            out
              ..write(negate ? '[^/' : '[')
              ..write(body.replaceAll(r'\', r'\\').replaceAll('[', r'\['))
              ..write(']');
            i = close;
          }
        default:
          out.write(RegExp.escape(char));
      }
      i++;
    }
    return (out..write(r'$')).toString();
  }

  /// The `]` closing the class opened at [open], or null.
  static int? _classEnd(String glob, int open) {
    var i = open + 1;
    if (i < glob.length && (glob[i] == '!' || glob[i] == '^')) i++;
    // A `]` first is one of the class.
    if (i < glob.length && glob[i] == ']') i++;
    while (i < glob.length) {
      if (glob[i] == ']') return i;
      if (glob[i] == '/') return null;
      i++;
    }
    return null;
  }
}

/// An ignore file and where it is: [prefix] leads from its folder to the
/// walk's root, and the first [strip] characters of a path from the root
/// lead to its folder.
class _Level {
  const _Level(this.rules, {this.prefix = '', this.strip = 0});

  final GitIgnore rules;
  final String prefix;
  final int strip;

  bool? decide(String relative, String name, bool isDirectory) => rules.decide(
    // Only anchored rules look at the path.
    !rules.isAnchored || (prefix.isEmpty && strip == 0)
        ? relative
        : '$prefix${relative.substring(strip)}',
    name,
    isDirectory: isDirectory,
  );
}

/// A file found by [walkUnignored]: its path from the root (with `/`) and
/// on disk.
typedef UnignoredFile = ({String relative, String path});

/// Every regular file under [root] that the ignore files leave, as ripgrep
/// walks one: each folder's `.gitignore` applies below it, a repository's
/// `.git/info/exclude` and the user's global ignore file too, and a
/// repository inside (a clone, a submodule) goes by its own. Those of the
/// repository [root] is in apply as well, and `.gitignore` files apply
/// outside any repository. Ignored folders are not gone into.
///
/// [skipDirectory] leaves out other folders (by their path from [root]);
/// [ignoreFiles] false reads no ignore files. Files come sorted within each
/// folder, lazily, so a search can start before the walk is done.
Iterable<UnignoredFile> walkUnignored(
  String root, {
  bool Function(String relative, String name)? skipDirectory,
  bool ignoreFiles = true,
}) sync* {
  final separator = Platform.pathSeparator;
  final base = ignoreFiles ? _rootLevels(root) : const <_Level>[];
  final global = ignoreFiles ? _globalLevel() : null;
  final pending = <(String, String, List<_Level>)>[(root, '', base)];
  while (pending.isNotEmpty) {
    final (directory, relative, inherited) = pending.removeLast();
    final List<FileSystemEntity> entries;
    try {
      entries = Directory(directory).listSync(followLinks: false);
    } on FileSystemException {
      continue;
    }
    final names = [for (final entry in entries) _name(entry.path, separator)];
    var levels = inherited;
    if (ignoreFiles) {
      final strip = relative.isEmpty ? 0 : relative.length + 1;
      // A repository inside: its own rules, not the outer one's.
      if (relative.isNotEmpty && names.contains('.git')) {
        levels = [
          ?global,
          ?_readLevel(
            p.join(directory, '.git', 'info', 'exclude'),
            strip: strip,
          ),
        ];
      }
      if (names.contains('.gitignore')) {
        if (_readLevel(p.join(directory, '.gitignore'), strip: strip)
            case final level?) {
          levels = [...levels, level];
        }
      }
    }
    final files = <UnignoredFile>[];
    final folders = <(String, String, List<_Level>)>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final isDirectory = entry is Directory;
      if (!isDirectory && entry is! File) continue;
      final name = names[i];
      final path = relative.isEmpty ? name : '$relative/$name';
      if (ignoreFiles) {
        if (isDirectory && name == '.git') continue;
        if (_ignored(levels, path, name, isDirectory)) continue;
      }
      if (isDirectory) {
        if (skipDirectory?.call(path, name) ?? false) continue;
        folders.add((entry.path, path, levels));
      } else {
        files.add((relative: path, path: entry.path));
      }
    }
    files.sort((a, b) => a.relative.compareTo(b.relative));
    yield* files;
    folders.sort((a, b) => b.$2.compareTo(a.$2));
    pending.addAll(folders);
  }
}

bool _ignored(List<_Level> levels, String path, String name, bool directory) {
  for (var i = levels.length - 1; i >= 0; i--) {
    if (levels[i].decide(path, name, directory) case final ignored?) {
      return ignored;
    }
  }
  return false;
}

String _name(String path, String separator) {
  final slash = path.lastIndexOf(separator);
  return slash < 0 ? path : path.substring(slash + 1);
}

_Level? _readLevel(String path, {String prefix = '', int strip = 0}) {
  final String text;
  try {
    text = File(path).readAsStringSync();
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
  final rules = GitIgnore.parse(text);
  if (rules.isEmpty) return null;
  return _Level(rules, prefix: prefix, strip: strip);
}

/// The user's global ignore file, at Git's default place.
_Level? _globalLevel() {
  final environment = Platform.environment;
  final config = environment['XDG_CONFIG_HOME'];
  final home = environment['HOME'] ?? environment['USERPROFILE'];
  final String folder;
  if (config != null && config.isNotEmpty) {
    folder = config;
  } else if (home != null && home.isNotEmpty) {
    folder = p.join(home, '.config');
  } else {
    return null;
  }
  return _readLevel(p.join(folder, 'git', 'ignore'));
}

/// The rules over [root] before its own `.gitignore`: the global ones, and
/// where [root] is in a repository, its `info/exclude` and the
/// `.gitignore` files of the folders between.
List<_Level> _rootLevels(String root) {
  final levels = [?_globalLevel()];
  final folders = <String>[];
  var folder = p.absolute(root);
  while (true) {
    if (FileSystemEntity.typeSync(p.join(folder, '.git'), followLinks: false) !=
        FileSystemEntityType.notFound) {
      break;
    }
    final parent = p.dirname(folder);
    if (parent == folder) return levels;
    folders.add(folder);
    folder = parent;
  }
  // [folder] is the repository; [folders] lead from [root] up to below it.
  // [root]'s own `.gitignore` is read by the walk.
  return [
    ...levels,
    ?_readLevel(
      p.join(folder, '.git', 'info', 'exclude'),
      prefix: _prefix(folder, root),
    ),
    if (folders.isNotEmpty)
      for (final above in [folder, ...folders.skip(1).toList().reversed])
        ?_readLevel(p.join(above, '.gitignore'), prefix: _prefix(above, root)),
  ];
}

/// The path from [folder] to [root], with `/` after; empty for [root].
String _prefix(String folder, String root) {
  final relative = p.relative(p.absolute(root), from: folder);
  return relative == '.' ? '' : '${relative.replaceAll(r'\', '/')}/';
}
