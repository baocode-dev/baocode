/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Parses possible links out of a line with only the line's text and the
// target operating system, without checking that the paths exist: paths with
// a line and column suffix (`foo:339:12`, `"foo", line 339, col 12`,
// `foo(339, 12)`, ...), then paths without one, and the file names of Git
// diffs.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminalContrib/links/browser/
// terminalLinkParsing.ts, with `OperatingSystem` from
// src/vs/base/common/platform.ts. The parsed shapes are records, so that
// they compare by value like upstream's object literals; `undefined` is
// null. Dart's `RegExp` is the same engine as JavaScript's (named groups,
// look-ahead, UTF-16 code units), so the expressions are upstream's.

/// The operating system a terminal's process runs on, which decides the path
/// syntax (upstream's `OperatingSystem`).
enum OperatingSystem { windows, macintosh, linux }

/// A link found in a line: its path, and the quote before and the line and
/// column suffix after it, which are underlined with it.
typedef IParsedLink = ({
  ILinkPartialRange path,
  ILinkPartialRange? prefix,
  ILinkSuffix? suffix,
});

/// A line and column suffix; [row] to [colEnd] are one-based.
typedef ILinkSuffix = ({
  int? row,
  int? col,
  int? rowEnd,
  int? colEnd,
  ILinkPartialRange suffix,
});

/// Part of a line: [text] at string [index].
typedef ILinkPartialRange = ({int index, String text});

/// A regex that extracts the link suffix which contains line and column
/// information. The link suffix must terminate at the end of line.
final RegExp _linkSuffixRegexEol = _generateLinkSuffixRegex(true);

/// A regex that extracts the link suffix which contains line and column
/// information.
final RegExp _linkSuffixRegex = _generateLinkSuffixRegex(false);

RegExp _generateLinkSuffixRegex(bool eolOnly) {
  var ri = 0;
  var ci = 0;
  var rei = 0;
  var cei = 0;
  String r() => '(?<row${ri++}>\\d+)';
  String c() => '(?<col${ci++}>\\d+)';
  String re() => '(?<rowEnd${rei++}>\\d+)';
  String ce() => '(?<colEnd${cei++}>\\d+)';

  final eolSuffix = eolOnly ? r'$' : '';

  // The comments in the regex below use real strings/numbers for better
  // readability, here's the legend:
  // - Path    = foo
  // - Row     = 339
  // - Col     = 12
  // - RowEnd  = 341
  // - ColEnd  = 789
  //
  // These all support single quote ' in the place of " and [] in the place
  // of ()
  //
  // See the tests for an exhaustive list of all supported formats
  final lineAndColumnRegexClauses = [
    // foo:339
    // foo:339:12
    // foo:339:12-789
    // foo:339:12-341.789
    // foo:339.12
    // foo 339
    // foo 339:12                              [#140780]
    // foo 339.12
    // foo#339
    // foo#339:12                              [#190288]
    // foo#339.12
    // foo, 339                                [#217927]
    // "foo",339
    // "foo",339:12
    // "foo",339.12
    // "foo",339.12-789
    // "foo",339.12-341.789
    '(?::|#| |[\'"],|, )${r()}([:.]${c()}(?:-(?:${re()}\\.)?${ce()})?)?'
        '$eolSuffix',
    // The quotes below are optional           [#171652]
    // "foo", line 339                         [#40468]
    // "foo", line 339, col 12
    // "foo", line 339, column 12
    // "foo":line 339
    // "foo":line 339, col 12
    // "foo":line 339, column 12
    // "foo": line 339
    // "foo": line 339, col 12
    // "foo": line 339, column 12
    // "foo" on line 339
    // "foo" on line 339, col 12
    // "foo" on line 339, column 12
    // "foo" line 339 column 12
    // "foo", line 339, character 12           [#171880]
    // "foo", line 339, characters 12-789      [#171880]
    // "foo", lines 339-341                    [#171880]
    // "foo", lines 339-341, characters 12-789 [#178287]
    '[\'"]?(?:,? |: ?| on )lines? ${r()}(?:-${re()})?'
        '(?:,? (?:col(?:umn)?|characters?) ${c()}(?:-${ce()})?)?$eolSuffix',
    // () and [] are interchangeable
    // foo(339)
    // foo(339,12)
    // foo(339, 12)
    // foo (339)
    // foo (339,12)
    // foo (339, 12)
    // foo: (339)
    // foo: (339,12)
    // foo: (339, 12)
    // foo(339:12)                             [#229842]
    // foo (339:12)                            [#229842]
    ':? ?[\\[\\(]${r()}(?:(?:, ?|:)${c()})?[\\]\\)]$eolSuffix',
  ];

  final suffixClause = lineAndColumnRegexClauses
      // Join all clauses together
      .join('|')
      // Convert spaces to allow the non-breaking space char (ascii 160)
      .replaceAll(' ', '[\u00A0 ]');

  return RegExp('($suffixClause)');
}

/// Removes the optional link suffix which contains line and column
/// information.
String removeLinkSuffix(String link) {
  final suffix = getLinkSuffix(link)?.suffix;
  if (suffix == null) {
    return link;
  }
  return link.substring(0, suffix.index);
}

/// Removes any query string from the link.
String removeLinkQueryString(String link) {
  // Skip ? in UNC paths
  final start = link.startsWith(r'\\?\') ? 4 : 0;
  final index = link.indexOf('?', start);
  if (index == -1) {
    return link;
  }
  return link.substring(0, index);
}

List<ILinkSuffix> detectLinkSuffixes(String line) {
  // Find all suffixes on the line. The matches do not overlap, as with
  // upstream's global regex and its lastIndex.
  final results = <ILinkSuffix>[];
  for (final match in _linkSuffixRegex.allMatches(line)) {
    final suffix = toLinkSuffix(match);
    if (suffix == null) {
      break;
    }
    results.add(suffix);
  }
  return results;
}

/// Returns the optional link suffix which contains line and column
/// information.
ILinkSuffix? getLinkSuffix(String link) {
  return toLinkSuffix(_linkSuffixRegexEol.firstMatch(link));
}

ILinkSuffix? toLinkSuffix(RegExpMatch? match) {
  if (match == null) {
    return null;
  }
  // Not every clause has every group (there is no `rowEnd2`): a missing
  // group reads as undefined upstream but throws in Dart.
  final names = match.groupNames;
  String? group(String name) {
    for (var i = 0; i < 3; i++) {
      final value = names.contains('$name$i')
          ? match.namedGroup('$name$i')
          : null;
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  return (
    row: _parseIntOptional(group('row')),
    col: _parseIntOptional(group('col')),
    rowEnd: _parseIntOptional(group('rowEnd')),
    colEnd: _parseIntOptional(group('colEnd')),
    suffix: (index: match.start, text: match[0]!),
  );
}

int? _parseIntOptional(String? value) {
  if (value == null) {
    return null;
  }
  return int.parse(value);
}

// This defines valid path characters for a link with a suffix, the first `[]`
// of the regex includes characters the path is not allowed to _start_ with,
// the second `[]` includes characters not allowed at all in the path. If the
// characters show up in both regexes the link will stop at that character,
// otherwise it will stop at a space character.
final RegExp _linkWithSuffixPathCharacters = RegExp(
  r'(?<path>(?:file:\/\/\/)?[^\s\|<>\[\({][^\s\|<>]*)$',
);

List<IParsedLink> detectLinks(String line, OperatingSystem os) {
  // 1: Detect all links on line via suffixes first
  final results = _detectLinksViaSuffix(line);

  // 2: Detect all links without suffixes and merge non-conflicting ranges
  // into the results
  final noSuffixPaths = _detectPathsNoSuffix(line, os);
  _binaryInsertList(results, noSuffixPaths);

  return results;
}

void _binaryInsertList(List<IParsedLink> list, List<IParsedLink> newItems) {
  if (list.isEmpty) {
    list.addAll(newItems);
  }
  for (final item in newItems) {
    _binaryInsert(list, item, 0, list.length);
  }
}

void _binaryInsert(
  List<IParsedLink> list,
  IParsedLink newItem,
  int low,
  int high,
) {
  if (list.isEmpty) {
    list.add(newItem);
    return;
  }
  if (low > high) {
    return;
  }
  // Find the index where the newItem would be inserted
  final mid = (low + high) ~/ 2;
  if (mid >= list.length ||
      (newItem.path.index < list[mid].path.index &&
          (mid == 0 || newItem.path.index > list[mid - 1].path.index))) {
    // Check if it conflicts with an existing link before adding
    if (mid >= list.length ||
        (newItem.path.index + newItem.path.text.length < list[mid].path.index &&
            (mid == 0 ||
                newItem.path.index >
                    list[mid - 1].path.index +
                        list[mid - 1].path.text.length))) {
      list.insert(mid, newItem);
    }
    return;
  }
  if (newItem.path.index > list[mid].path.index) {
    _binaryInsert(list, newItem, mid + 1, high);
  } else {
    _binaryInsert(list, newItem, low, mid - 1);
  }
}

final RegExp _prefixRegex = RegExp(r'''^(?<prefix>['"]+)''');
final RegExp _quoteRegex = RegExp(r'''['"]''');
final RegExp _openingBracketRegex = RegExp(r'(?<bracket>[\[\(])(?![\]\)])');

List<IParsedLink> _detectLinksViaSuffix(String line) {
  final results = <IParsedLink>[];

  // 1: Detect link suffixes on the line
  final suffixes = detectLinkSuffixes(line);
  for (final suffix in suffixes) {
    // Ignore suffixes followed by `/` so numeric Git diff prefixes such as
    // `1/` are parsed as paths.
    final suffixEndIndex = suffix.suffix.index + suffix.suffix.text.length;
    if (suffixEndIndex < line.length && line[suffixEndIndex] == '/') {
      continue;
    }
    final beforeSuffix = line.substring(0, suffix.suffix.index);
    final possiblePathMatch = _linkWithSuffixPathCharacters.firstMatch(
      beforeSuffix,
    );
    final possiblePath = possiblePathMatch?.namedGroup('path');
    if (possiblePathMatch != null &&
        possiblePath != null &&
        possiblePath.isNotEmpty) {
      var linkStartIndex = possiblePathMatch.start;
      var path = possiblePath;
      // Extract a path prefix if it exists (not part of the path, but part of
      // the underlined section)
      ILinkPartialRange? prefix;
      final prefixMatch = _prefixRegex.firstMatch(path);
      final prefixText = prefixMatch?.namedGroup('prefix');
      if (prefixText != null && prefixText.isNotEmpty) {
        prefix = (index: linkStartIndex, text: prefixText);
        path = path.substring(prefix.text.length);

        // Don't allow suffix links to be returned when the link itself is
        // the empty string
        if (path.trim().isEmpty) {
          continue;
        }

        // If there are multiple characters in the prefix, trim the prefix if
        // the _first_ suffix character is the same as the last prefix
        // character. For example, for the text `echo "'foo' on line 1"`:
        //
        // - Prefix='
        // - Path=foo
        // - Suffix=' on line 1
        //
        // If this fails on a multi-character prefix, just keep the original.
        if (prefixText.length > 1) {
          if (_quoteRegex.hasMatch(suffix.suffix.text[0]) &&
              prefixText[prefixText.length - 1] == suffix.suffix.text[0]) {
            final trimPrefixAmount = prefixText.length - 1;
            prefix = (
              index: prefix.index + trimPrefixAmount,
              text: prefixText[prefixText.length - 1],
            );
            linkStartIndex += trimPrefixAmount;
          }
        }
      }
      results.add((
        path: (index: linkStartIndex + (prefix?.text.length ?? 0), text: path),
        prefix: prefix,
        suffix: suffix,
      ));

      // If the path contains an opening bracket, provide the path starting
      // immediately after the opening bracket as an additional result
      for (final match in _openingBracketRegex.allMatches(path)) {
        final bracket = match.namedGroup('bracket');
        if (bracket != null && bracket.isNotEmpty) {
          results.add((
            path: (
              index:
                  linkStartIndex + (prefix?.text.length ?? 0) + match.start + 1,
              text: path.substring(match.start + bracket.length),
            ),
            prefix: prefix,
            suffix: suffix,
          ));
        }
      }
    }
  }

  return results;
}

abstract final class _RegexPathConstants {
  static const pathPrefix = r'(?:\.\.?|\~|file:\/\/)';
  static const pathSeparatorClause = r'\/';
  // '":; are allowed in paths but they are often separators so ignore them
  // Also disallow \\ to prevent a catastropic backtracking case #24795
  static const excludedPathCharactersClause = r'''[^\0<>\?\s!`&*()'":;\\]''';
  static const excludedStartPathCharactersClause =
      r'''[^\0<>\?\s!`&*()\[\]'":;\\]''';

  static const winOtherPathPrefix = r'\.\.?|\~';
  static const winPathSeparatorClause = r'(?:\\|\/)';
  static const winExcludedPathCharactersClause =
      r'''[^\0<>\?\|\/\s!`&*()'":;]''';
  static const winExcludedStartPathCharactersClause =
      r'''[^\0<>\?\|\/\s!`&*()\[\]'":;]''';
}

/// A regex that matches non-Windows paths, such as `/foo`, `~/foo`, `./foo`,
/// `../foo` and `foo/bar`.
const String _unixLocalLinkClause =
    '(?:(?:${_RegexPathConstants.pathPrefix}|(?:'
    '${_RegexPathConstants.excludedStartPathCharactersClause}'
    '${_RegexPathConstants.excludedPathCharactersClause}*))?(?:'
    '${_RegexPathConstants.pathSeparatorClause}(?:'
    '${_RegexPathConstants.excludedPathCharactersClause})+)+)';

/// A regex clause that matches the start of an absolute path on Windows, such
/// as: `C:`, `c:`, `file:///c:` (uri) and `\\?\C:` (UNC path).
const String winDrivePrefix = r'(?:\\\\\?\\|file:\/\/\/)?[a-zA-Z]:';

/// A regex that matches Windows paths, such as `\\?\c:\foo`, `c:\foo`,
/// `~\foo`, `.\foo`, `..\foo` and `foo\bar`.
const String _winLocalLinkClause =
    '(?:(?:(?:$winDrivePrefix|${_RegexPathConstants.winOtherPathPrefix})|(?:'
    '${_RegexPathConstants.winExcludedStartPathCharactersClause}'
    '${_RegexPathConstants.winExcludedPathCharactersClause}*))?(?:'
    '${_RegexPathConstants.winPathSeparatorClause}(?:'
    '${_RegexPathConstants.winExcludedPathCharactersClause})+)+)';

/// A regex clause that matches the known single-character prefixes used in
/// git diffs. When diff.mnemonicPrefix is enabled, Git uses mnemonic letter
/// prefixes and uses 1/ and 2/ for `git diff --no-index`.
const String _diffFilePrefix = r'[abciow12]\/';

/// A regex that matches git diff lines with filenames, such as `--- a/foo`,
/// `+++ b/foo`.
final RegExp _gitDiffLineRegex = RegExp('^[-+]{3} $_diffFilePrefix');

/// A regex that matches filenames in lines like `diff --git a/foo b/foo`
/// without the prefix.
final RegExp _gitDiffTextRegex = RegExp('^$_diffFilePrefix');

final RegExp _unixLocalLinkRegex = RegExp(_unixLocalLinkClause);
final RegExp _winLocalLinkRegex = RegExp(_winLocalLinkClause);

List<IParsedLink> _detectPathsNoSuffix(String line, OperatingSystem os) {
  final results = <IParsedLink>[];

  final regex = os == OperatingSystem.windows
      ? _winLocalLinkRegex
      : _unixLocalLinkRegex;
  for (final match in regex.allMatches(line)) {
    var text = match[0]!;
    var index = match.start;
    if (text.isEmpty) {
      // Something matched but does not comply with the given match index,
      // since this would most likely a bug the regex itself we simply do
      // nothing here
      break;
    }

    // Adjust the link range to exclude a known Git diff prefix
    if (
    // --- a/foo/bar
    // +++ b/foo/bar
    (_gitDiffLineRegex.hasMatch(line) && index == 4) ||
        // diff --git a/foo/bar b/foo/bar
        (line.startsWith('diff --git') && _gitDiffTextRegex.hasMatch(text))) {
      text = text.substring(2);
      index += 2;
    }

    results.add((path: (index: index, text: text), prefix: null, suffix: null));
  }

  return results;
}
