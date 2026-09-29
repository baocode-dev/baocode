/// How the catalog matches a file to a language, as Helix does: exact names,
/// dotted extensions, path globs and `#!` interpreters.
library;

/// A Helix `{ glob = … }` file type, matched against a whole path.
///
/// Like Helix (globset with `literal_separator` off), `*` and `?` also match
/// `/`, and a pattern not starting with `/` or `*/` gets a leading `*/`, so
/// `.github/workflows/*.yml` matches that suffix of any path. `**`, `[…]`,
/// `[!…]` and `{a,b}` work as in globset.
class LspGlob {
  LspGlob(this.pattern) : _regExp = _compile(pattern);

  final String pattern;
  final RegExp _regExp;

  /// Whether [path] (either separator) matches. A relative path is taken as
  /// if under some folder, so `Dockerfile` matches `*/Dockerfile`.
  bool matches(String path) {
    var normalized = path.replaceAll('\\', '/');
    if (!normalized.startsWith('/')) normalized = '/$normalized';
    return _regExp.hasMatch(normalized);
  }

  static RegExp _compile(String pattern) {
    final glob = pattern.startsWith('/') || pattern.startsWith('*/')
        ? pattern
        : '*/$pattern';
    final out = StringBuffer('^');
    var braces = 0;
    for (var i = 0; i < glob.length; i++) {
      final c = glob[i];
      switch (c) {
        case '*':
          while (i + 1 < glob.length && glob[i + 1] == '*') {
            i++;
          }
          out.write('.*');
        case '?':
          out.write('.');
        case '[':
          final close = glob.indexOf(']', i + 2);
          if (close < 0) {
            out.write(r'\[');
            break;
          }
          var body = glob.substring(i + 1, close);
          final negated = body.startsWith('!') || body.startsWith('^');
          if (negated) body = body.substring(1);
          out
            ..write(negated ? '[^' : '[')
            ..write(body.replaceAll(r'\', r'\\').replaceAll('[', r'\['))
            ..write(']');
          i = close;
        case '{':
          braces++;
          out.write('(?:');
        case '}' when braces > 0:
          braces--;
          out.write(')');
        case ',' when braces > 0:
          out.write('|');
        case r'\' when i + 1 < glob.length:
          i++;
          out.write(RegExp.escape(glob[i]));
        default:
          out.write(RegExp.escape(c));
      }
    }
    if (braces > 0) throw FormatException('Unclosed { in glob', pattern);
    out.write(r'$');
    return RegExp(out.toString());
  }
}

final _shebang = RegExp(r'^#!\s*(?:\S*[/\\](?:env\s+(?:-\S+\s+)*)?)?(\S+)');

/// The interpreter names a `#!` [firstLine] may be listed under, most
/// specific first: `#!/usr/bin/env python3.12` gives `python3.12`, then
/// `python` (Helix's own reading drops version digits and dots).
List<String> shebangCandidates(String? firstLine) {
  if (firstLine == null) return const [];
  final match = _shebang.firstMatch(firstLine);
  if (match == null) return const [];
  final token = match[1]!;
  final unversioned = token.replaceFirst(RegExp(r'[\d.]+$'), '');
  final helix = RegExp(r'^[^\s.\d]+').firstMatch(token)?[0];
  return [
    ...{
      token,
      if (unversioned.isNotEmpty) unversioned,
      if (helix != null && helix.isNotEmpty) helix,
    },
  ];
}

/// The dotted suffixes of a base [name], longest first: `a.test.ts` gives
/// `test.ts`, `ts`; `.bashrc` gives `bashrc`.
List<String> extensionCandidates(String name) {
  final out = <String>[];
  for (var i = name.indexOf('.'); i >= 0; i = name.indexOf('.', i + 1)) {
    if (i + 1 < name.length) out.add(name.substring(i + 1));
  }
  return out;
}

/// The last segment of [path], for either separator.
String baseName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  return slash < 0 ? normalized : normalized.substring(slash + 1);
}
