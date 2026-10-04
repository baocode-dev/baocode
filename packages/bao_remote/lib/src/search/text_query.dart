/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The Search view's queries: the pattern and its options, the files to
// include and exclude, the matches, and replace strings.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/base/common/strings.ts (`createRegExp`, `lcut`),
// src/vs/base/common/glob.ts, src/vs/workbench/services/search/common/
// queryBuilder.ts (the include and exclude patterns),
// src/vs/workbench/services/search/common/replace.ts (`ReplacePattern`)
// and src/vs/base/common/search.ts (`buildReplaceStringWithCasePreserved`).
//
// Deviations: a pattern matches within a line, never across lines.

/// What to search for, and where.
class IdeTextQuery {
  const IdeTextQuery(
    this.pattern, {
    this.isRegExp = false,
    this.isCaseSensitive = false,
    this.isWordMatch = false,
    this.includes = '',
    this.excludes = '',
    this.useExcludesAndIgnoreFiles = true,
    this.maxResults = 20000,
  });

  final String pattern;
  final bool isRegExp;
  final bool isCaseSensitive;
  final bool isWordMatch;

  /// "files to include" and "files to exclude": comma-separated globs.
  final String includes;
  final String excludes;

  /// Use Exclude Settings and Ignore Files: the default excludes and
  /// `.gitignore`.
  final bool useExcludesAndIgnoreFiles;

  /// `search.maxResults`.
  final int maxResults;

  /// The pattern as a regular expression; throws a [FormatException] for
  /// an invalid one.
  RegExp toRegExp() => ideCreateRegExp(
    pattern,
    isRegExp: isRegExp,
    matchCase: isCaseSensitive,
    wholeWord: isWordMatch,
  );

  /// Whether [relativePath] (with `/`) is to be searched.
  bool Function(String relativePath) pathFilter() {
    final include = ideSearchPathGlobs(includes);
    final exclude = [
      ...ideSearchPathGlobs(excludes),
      if (useExcludesAndIgnoreFiles) ...ideDefaultSearchExcludes,
    ];
    return (path) =>
        (include.isEmpty || include.any((glob) => glob.hasMatch(path))) &&
        !exclude.any((glob) => glob.hasMatch(path));
  }
}

/// One occurrence: [line] (zero-based) and its [start] and [end] in the
/// line's [text] (UTF-16 offsets).
class IdeTextMatch {
  const IdeTextMatch(this.line, this.start, this.end, this.text);

  final int line;
  final int start;
  final int end;
  final String text;

  String get matched => text.substring(start, end);
}

/// A file's matches, in order.
class IdeFileMatches {
  const IdeFileMatches(this.path, this.matches);

  final String path;
  final List<IdeTextMatch> matches;
}

/// The end of a search: whether [maxResults](IdeTextQuery.maxResults) cut
/// it short.
class IdeTextSearchComplete {
  const IdeTextSearchComplete({required this.limitHit});

  final bool limitHit;
}

/// Searches the files under a root: each file's matches as they are found,
/// then [IdeTextSearchComplete]. Cancelling the subscription stops it.
typedef IdeTextSearch = Stream<Object> Function(
  String root,
  IdeTextQuery query,
);

/// `files.exclude` and `search.exclude`'s defaults.
final ideDefaultSearchExcludes = [
  for (final glob in const [
    '**/.git',
    '**/.svn',
    '**/.hg',
    '**/.DS_Store',
    '**/Thumbs.db',
    '**/node_modules',
    '**/bower_components',
    '**/*.code-search',
  ]) ...[ideGlob(glob), ideGlob('$glob/**')],
];

/// `strings.createRegExp`.
RegExp ideCreateRegExp(
  String searchString, {
  required bool isRegExp,
  bool matchCase = false,
  bool wholeWord = false,
}) {
  if (searchString.isEmpty) throw const FormatException('Empty pattern');
  var source = isRegExp ? searchString : RegExp.escape(searchString);
  if (wholeWord) {
    final word = RegExp(r'\w');
    if (word.hasMatch(source[0])) source = '\\b$source';
    if (word.hasMatch(source[source.length - 1])) source = '$source\\b';
  }
  return RegExp(source, caseSensitive: matchCase, unicode: true);
}

/// A glob as a regular expression over `/`-separated paths: `**` any
/// folders, `*` and `?` within a name, `{a,b}` and `[...]`.
RegExp ideGlob(String glob) {
  final out = StringBuffer('^');
  var braces = 0;
  for (var i = 0; i < glob.length; i++) {
    final char = glob[i];
    switch (char) {
      case '*':
        if (i + 1 < glob.length && glob[i + 1] == '*') {
          final atStart = i == 0 || glob[i - 1] == '/';
          if (atStart && i + 2 < glob.length && glob[i + 2] == '/') {
            // `**/`: any folders, or none.
            out.write('(?:.*/)?');
            i += 2;
          } else {
            out.write('.*');
            i += 1;
          }
        } else {
          out.write('[^/]*');
        }
      case '?':
        out.write('[^/]');
      case '{':
        braces++;
        out.write('(?:');
      case '}' when braces > 0:
        braces--;
        out.write(')');
      case ',' when braces > 0:
        out.write('|');
      case '[':
        final close = glob.indexOf(']', i + 1);
        if (close < 0) {
          out.write(r'\[');
        } else {
          var set = glob.substring(i + 1, close);
          if (set.startsWith('!')) set = '^${set.substring(1)}';
          out.write('[${set.replaceAll(r'\', r'\\')}]');
          i = close;
        }
      default:
        out.write(RegExp.escape(char));
    }
  }
  out.write(r'$');
  return RegExp(out.toString());
}

/// The globs of "files to include" or "files to exclude" (queryBuilder's
/// `parseSearchPaths`): `./src` is under the root, anything else anywhere;
/// a folder matches what is in it.
List<RegExp> ideSearchPathGlobs(String patterns) {
  final globs = <RegExp>[];
  for (var pattern in _splitGlobs(patterns)) {
    pattern = pattern.trim().replaceAll(r'\', '/');
    if (pattern.isEmpty) continue;
    while (pattern.length > 1 && pattern.endsWith('/')) {
      pattern = pattern.substring(0, pattern.length - 1);
    }
    if (pattern.startsWith('./')) {
      pattern = pattern.substring(2);
    } else if (!pattern.startsWith('**') && !pattern.startsWith('/')) {
      pattern = '**/$pattern';
    } else if (pattern.startsWith('/')) {
      pattern = pattern.substring(1);
    }
    if (pattern.isEmpty || pattern == '.') {
      globs.add(RegExp('.*'));
      continue;
    }
    globs
      ..add(ideGlob(pattern))
      ..add(ideGlob(pattern.endsWith('/**') ? pattern : '$pattern/**'));
  }
  return globs;
}

/// Splits at commas outside braces.
Iterable<String> _splitGlobs(String patterns) sync* {
  var depth = 0;
  var start = 0;
  for (var i = 0; i < patterns.length; i++) {
    final char = patterns[i];
    if (char == '{') depth++;
    if (char == '}' && depth > 0) depth--;
    if (char == ',' && depth == 0) {
      yield patterns.substring(start, i);
      start = i + 1;
    }
  }
  yield patterns.substring(start);
}

/// Matches [regExp] in [text], line by line, up to [limit].
List<IdeTextMatch> ideMatchLines(String text, RegExp regExp, {int? limit}) {
  final matches = <IdeTextMatch>[];
  var line = 0;
  var start = 0;
  while (start <= text.length) {
    var end = text.indexOf('\n', start);
    if (end < 0) end = text.length;
    var lineEnd = end;
    if (lineEnd > start && text.codeUnitAt(lineEnd - 1) == 0x0D) lineEnd--;
    final lineText = text.substring(start, lineEnd);
    for (final match in regExp.allMatches(lineText)) {
      if (match.end == match.start) continue;
      matches.add(IdeTextMatch(line, match.start, match.end, lineText));
      if (limit != null && matches.length >= limit) return matches;
    }
    if (end == text.length) break;
    start = end + 1;
    line++;
  }
  return matches;
}

/// The Search view's match preview (`Match.preview`): what comes before
/// (cut to 26 characters at a word boundary), the match, and after, within
/// 250 characters.
({String before, String inside, String after}) ideMatchPreview(
  IdeTextMatch match,
) {
  const maxPreview = 250;
  final before = ideLcut(match.text.substring(0, match.start), 26, '…');
  var remaining = maxPreview - before.length;
  var inside = match.matched;
  if (inside.length > remaining) inside = inside.substring(0, remaining);
  remaining -= inside.length;
  var after = match.text.substring(match.end);
  if (after.length > remaining) after = after.substring(0, remaining);
  return (before: before, inside: inside, after: after);
}

/// `strings.lcut`: the end of [text] within [n] characters, starting at a
/// word boundary, [prefix]ed when cut.
String ideLcut(String text, int n, [String prefix = '']) {
  final trimmed = text.trimLeft();
  if (trimmed.length < n) return trimmed;
  var cut = 0;
  for (final boundary in RegExp(r'\b').allMatches(trimmed)) {
    if (trimmed.length - boundary.start < n) break;
    cut = boundary.start;
  }
  if (cut == 0) return trimmed;
  return prefix + trimmed.substring(cut).trimLeft();
}

/// The text replacing [match] ([ReplacePattern]): a regular expression's
/// `$1`, `$&` and `\n`, and with [preserveCase] the match's case.
String ideReplaceString(
  IdeTextMatch match,
  String replace, {
  required RegExp regExp,
  required bool isRegExp,
  bool preserveCase = false,
}) {
  var result = replace;
  if (isRegExp) {
    final found = regExp.matchAsPrefix(match.text, match.start);
    result = _expandReplace(replace, found);
  }
  return preserveCase ? ideReplaceCasePreserved(match.matched, result) : result;
}

String _expandReplace(String replace, Match? match) {
  final out = StringBuffer();
  for (var i = 0; i < replace.length; i++) {
    final char = replace[i];
    if (char == r'\' && i + 1 < replace.length) {
      final next = replace[i + 1];
      switch (next) {
        case 'n':
          out.write('\n');
          i++;
          continue;
        case 't':
          out.write('\t');
          i++;
          continue;
        case r'\':
          out.write(r'\');
          i++;
          continue;
      }
    }
    if (char == r'$' && i + 1 < replace.length) {
      final next = replace[i + 1];
      if (next == r'$') {
        out.write(r'$');
        i++;
        continue;
      }
      if (next == '&') {
        out.write(match?[0] ?? '');
        i++;
        continue;
      }
      final digits = RegExp(r'\d{1,2}').matchAsPrefix(replace, i + 1);
      if (digits != null && match != null) {
        var group = int.parse(digits[0]!);
        var length = digits[0]!.length;
        if (group > match.groupCount && length == 2) {
          group ~/= 10;
          length = 1;
        }
        if (group >= 1 && group <= match.groupCount) {
          out.write(match[group] ?? '');
          i += length;
          continue;
        }
      }
    }
    out.write(char);
  }
  return out.toString();
}

/// `buildReplaceStringWithCasePreserved`, for the common cases: all upper,
/// all lower, and capitalized.
String ideReplaceCasePreserved(String matched, String replace) {
  if (matched.isEmpty || replace.isEmpty) return replace;
  if (matched == matched.toUpperCase() && matched != matched.toLowerCase()) {
    return replace.toUpperCase();
  }
  if (matched == matched.toLowerCase() && matched != matched.toUpperCase()) {
    return replace.toLowerCase();
  }
  final first = matched[0];
  if (first == first.toUpperCase() && first != first.toLowerCase()) {
    return replace[0].toUpperCase() + replace.substring(1);
  }
  return replace;
}
