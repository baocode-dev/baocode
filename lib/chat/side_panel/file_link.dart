import 'package:path/path.dart' as p;

/// Lines of a file, from 1: [start] to [end], at [column] (from 1) when
/// one is said.
class FileLineRange {
  const FileLineRange(this.start, [int? end, this.column])
    : end = end == null || end < start ? start : end;

  final int start;
  final int end;
  final int? column;

  /// A Read's detail as the chat shows it (`L10-60`); null for any other.
  static FileLineRange? parseDetail(String? detail) {
    final match = RegExp(r'^L(\d+)(?:-(\d+))?$').firstMatch(detail ?? '');
    if (match == null) return null;
    final start = int.parse(match[1]!);
    if (start < 1) return null;
    return FileLineRange(start, int.tryParse(match[2] ?? ''));
  }

  /// `Ln 14–16`, or `Ln 14` for a line.
  String get label => start == end ? 'Ln $start' : 'Ln $start–$end';

  @override
  bool operator ==(Object other) =>
      other is FileLineRange &&
      other.start == start &&
      other.end == end &&
      other.column == column;

  @override
  int get hashCode => Object.hash(start, end, column);

  @override
  String toString() =>
      'FileLineRange($start, $end${column == null ? '' : ', $column'})';
}

/// A file the agent pointed at: a markdown link's address
/// (`[a.dart](lib/a.dart#L12)`, as `ClaudeLaunch.fileLinks` asks it to
/// write them), a path in inline code (`lib/a.dart:12`, as Claude Code's
/// own prompt has it), or a search's match. [path] as written: relative to
/// where the agent works, or absolute; on another [machine] than that.
class FileLink {
  const FileLink(this.path, [this.range]) : machine = null;

  /// A file of [machine]'s: [userComputer], or an SSH host.
  const FileLink.on(this.machine, this.path, [this.range]);

  final String path;
  final FileLineRange? range;

  /// Where the file is when that is not where the agent works:
  /// [userComputer] (`local:/a/b.dart`, from an agent on an SSH host), or
  /// an SSH host (`ssh://host/a/b.dart`, as the app names a host's file,
  /// see `RemoteLocation`). Null for where the agent works.
  final String? machine;

  /// The user's own computer, as [machine]: no host is named `''`.
  static const userComputer = '';

  /// The scheme of a link to a file of the user's own computer.
  static const userComputerScheme = 'local:';

  /// The scheme of a link to a file of an SSH host.
  static const sshScheme = 'ssh://';

  /// The file a link to [href] goes to; null for a web, mail or any other
  /// scheme's address, a heading's anchor, or nothing.
  static FileLink? parseHref(String? href) {
    var text = href?.trim() ?? '';
    // `<a b.dart>`, should the brackets come through.
    if (text.startsWith('<') && text.endsWith('>')) {
      text = text.substring(1, text.length - 1).trim();
    }
    if (text.isEmpty || text.startsWith('#')) return null;
    final lower = text.toLowerCase();
    if (lower.startsWith(userComputerScheme)) {
      var rest = text.substring(userComputerScheme.length);
      // `local:///a/b.dart`, as a URL would be.
      if (rest.startsWith('//')) rest = rest.substring(2);
      return _on(userComputer, rest);
    }
    if (lower.startsWith(sshScheme)) {
      final rest = text.substring(sshScheme.length);
      final slash = rest.indexOf('/');
      if (slash <= 0) return null;
      return _on(rest.substring(0, slash), rest.substring(slash));
    }
    if (_scheme.firstMatch(text) case final match?
        when !_drive.hasMatch(text)) {
      if (match[1]!.toLowerCase() != 'file') return null;
      final uri = Uri.tryParse(text);
      if (uri == null) return null;
      // `file:///C:/a.dart`.
      final path = _driveOf(_decode(uri.path));
      if (path.isEmpty) return null;
      final range = _fragment(uri.hasFragment ? uri.fragment : null);
      return range == null ? _withSuffix(path) : FileLink(path, range);
    }
    final hash = text.indexOf('#');
    // `/C:/a.dart`, as a URL's path would be: a Windows model's, told to
    // write the absolute path after a slash.
    final path = _driveOf(_decode(hash < 0 ? text : text.substring(0, hash)));
    if (path.isEmpty) return null;
    if (hash >= 0) {
      final range = _fragment(text.substring(hash + 1));
      // `a.md#usage`: the file, its heading not followed.
      return FileLink(path, range);
    }
    return _withSuffix(path);
  }

  /// The file at [address] (an absolute path, with a line after it or
  /// not) of [machine]'s; null for none, or a relative path: where it is
  /// from is not known there.
  static FileLink? _on(String machine, String address) {
    final hash = address.indexOf('#');
    // `/C:/a/b.dart`, a Windows host's, as the app's locations spell it.
    final path = _driveOf(
      _decode(hash < 0 ? address : address.substring(0, hash)),
    );
    final FileLink link;
    if (hash >= 0) {
      link = FileLink(path, _fragment(address.substring(hash + 1)));
    } else {
      link = _withSuffix(path);
    }
    final absolute = link.path.startsWith('/') || _drive.hasMatch(link.path);
    if (!absolute) return null;
    return FileLink.on(machine, link.path, link.range);
  }

  /// The file inline code names (`lib/a.dart`, `lib/a.dart:12:5`,
  /// `a.dart#L3-L9`); null for code that does not look like a path: with
  /// blanks, quotes or brackets in it, an address, or a word without a
  /// folder or an extension. [blanks] lets a path have spaces (a search's
  /// match).
  static FileLink? parseText(String text, {bool blanks = false}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > 400) return null;
    if (!blanks && RegExp(r'\s').hasMatch(trimmed)) return null;
    if (RegExp('["\'`(){}<>|*?;,=\$]').hasMatch(trimmed)) return null;
    if (trimmed.contains('://')) return null;
    final hash = trimmed.indexOf('#');
    final FileLink link;
    if (hash >= 0) {
      final range = _fragment(trimmed.substring(hash + 1));
      if (range == null) return null;
      link = FileLink(trimmed.substring(0, hash), range);
    } else {
      link = _withSuffix(trimmed);
    }
    return _pathLike(link.path) ? link : null;
  }

  /// [path] made absolute from [root] (in [paths]' spelling; this
  /// machine's when null): see [resolvePath].
  String? resolveIn(String root, {p.Context? paths, String? home}) =>
      resolvePath(path, root, paths: paths, home: home);

  /// [path] absolute, as the agent's own tools take it (bao_agent's
  /// `PermissionEngine.absolute`): `~` the [home] folder of the host,
  /// relative to [root] (where the agent works), wherever that leads, in
  /// the project or out of it. Null for nothing, `~` without a [home], or
  /// another user's (`~bob`).
  static String? resolvePath(
    String path,
    String root, {
    p.Context? paths,
    String? home,
  }) {
    final context = paths ?? p.context;
    if (path.isEmpty) return null;
    // `/C:/a.dart` (a code citation's, inline code's): rooted at no drive
    // on Windows, where it is the drive's.
    var expanded = context.style == p.Style.windows ? _driveOf(path) : path;
    if (path.startsWith('~')) {
      final rest = path.substring(1);
      if (home == null || home.isEmpty) return null;
      if (rest.isEmpty) {
        expanded = home;
      } else if (rest.startsWith('/') ||
          (context.style == p.Style.windows && rest.startsWith(r'\'))) {
        expanded = context.join(home, rest.substring(1));
      } else {
        return null;
      }
    }
    return context.normalize(
      context.isAbsolute(expanded) ? expanded : context.join(root, expanded),
    );
  }

  /// A scheme (`https:`, `vscode:`); a drive (`C:`) is not one.
  static final _scheme = RegExp(r'^([A-Za-z][A-Za-z0-9+.-]*):');
  static final _drive = RegExp(r'^[A-Za-z]:([/\\]|$)');

  /// [path] without the slash before a drive (`/C:/a.dart`, a URL's way
  /// of writing `C:/a.dart`): the path itself.
  static String _driveOf(String path) =>
      _slashedDrive.hasMatch(path) ? path.substring(1) : path;
  static final _slashedDrive = RegExp(r'^/[A-Za-z]:([/\\]|$)');

  /// `L12`, `L12-L20`, `L12-20`, `L12C5`, `12`; null for a heading's.
  static FileLineRange? _fragment(String? fragment) {
    final match = RegExp(
      r'^L?(\d+)(?:C(\d+))?(?:-L?(\d+)(?:C\d+)?)?$',
      caseSensitive: false,
    ).firstMatch(fragment?.trim() ?? '');
    if (match == null) return null;
    final start = int.parse(match[1]!);
    if (start < 1) return null;
    return FileLineRange(
      start,
      int.tryParse(match[3] ?? ''),
      int.tryParse(match[2] ?? ''),
    );
  }

  /// [text] with a line, a line and column, or lines after it taken off:
  /// `a.dart:12`, `a.dart:12:5`, `a.dart:12-20`.
  static FileLink _withSuffix(String text) {
    final match = RegExp(r'^(.+?):(\d+)(?::(\d+)|-(\d+))?$').firstMatch(text);
    // Not a drive's letter (`C:12`).
    if (match == null || match[1]!.length < 2) return FileLink(text);
    final start = int.parse(match[2]!);
    if (start < 1) return FileLink(text);
    return FileLink(
      match[1]!,
      FileLineRange(
        start,
        int.tryParse(match[4] ?? ''),
        int.tryParse(match[3] ?? ''),
      ),
    );
  }

  /// A folder in it, or a name with an extension: `lib/a.dart`,
  /// `README.md`, `C:\a\b.rs`; not `foo`, `1.5`, `...`, `-v`.
  static bool _pathLike(String path) {
    if (path.isEmpty || path.startsWith('-')) return false;
    if (path.contains('/') || path.contains(r'\')) {
      // Not a bare `/` or `//`.
      return RegExp(r'[A-Za-z0-9_]').hasMatch(path);
    }
    return RegExp(r'^[\w@.+-]*[A-Za-z_][\w@+-]*\.[A-Za-z][\w]{0,9}$')
        .hasMatch(path);
  }

  static String _decode(String text) {
    if (!text.contains('%')) return text;
    try {
      return Uri.decodeComponent(text);
    } on ArgumentError {
      return text;
    } on FormatException {
      return text;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is FileLink &&
      other.path == path &&
      other.range == range &&
      other.machine == machine;

  @override
  int get hashCode => Object.hash(path, range, machine);

  @override
  String toString() =>
      'FileLink(${machine == null ? '' : '${machine!.isEmpty ? 'local' : machine}: '}'
      '$path, $range)';
}
