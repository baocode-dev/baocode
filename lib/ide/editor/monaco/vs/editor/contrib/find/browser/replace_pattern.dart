/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/
// Port of VS Code src/vs/editor/contrib/find/browser/replacePattern.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971. The preserve-case helper is
// ported from src/vs/base/common/search.ts at the same revision.
//
// A JS RegExp.exec result has a non-null full match and may have undefined
// optional captures. Dart callers pass those captures as null in List<String?>.
// JS RegExp metadata (index, input, groups) is unused by this source. Casing
// uses Dart's Unicode case mapping; it may differ from JavaScript's for some
// Unicode characters or revisions of the Unicode data.

/// A literal or a captured-group reference in a replacement string.
class ReplacePiece {
  ReplacePiece._(this.staticValue, this.matchIndex, List<String>? caseOps)
    : caseOps = caseOps == null || caseOps.isEmpty ? null : List.of(caseOps);

  factory ReplacePiece.staticValue(String value) =>
      ReplacePiece._(value, -1, null);

  factory ReplacePiece.matchIndex(int index) =>
      ReplacePiece._(null, index, null);

  factory ReplacePiece.caseOps(int index, List<String> caseOps) =>
      ReplacePiece._(null, index, caseOps);

  final String? staticValue;
  final int matchIndex;
  final List<String>? caseOps;
}

/// The parsed replacement, either entirely static or made of dynamic pieces.
class ReplacePattern {
  ReplacePattern(List<ReplacePiece>? pieces)
    : _staticValue = pieces == null || pieces.isEmpty
          ? ''
          : pieces.length == 1 && pieces[0].staticValue != null
          ? pieces[0].staticValue
          : null,
      _pieces =
          pieces != null &&
              pieces.isNotEmpty &&
              !(pieces.length == 1 && pieces[0].staticValue != null)
          ? pieces
          : null;

  factory ReplacePattern.fromStaticValue(String value) =>
      ReplacePattern([ReplacePiece.staticValue(value)]);

  final String? _staticValue;
  final List<ReplacePiece>? _pieces;

  bool get hasReplacementPatterns => _pieces != null;

  String buildReplaceString(
    List<String?>? matches, [
    bool preserveCase = false,
  ]) {
    final staticValue = _staticValue;
    if (staticValue != null) {
      return preserveCase
          ? buildReplaceStringWithCasePreserved(matches, staticValue)
          : staticValue;
    }

    final result = StringBuffer();
    for (final piece in _pieces!) {
      if (piece.staticValue != null) {
        result.write(piece.staticValue);
        continue;
      }

      var match = _substitute(piece.matchIndex, matches);
      final caseOps = piece.caseOps;
      if (caseOps != null && caseOps.isNotEmpty) {
        final repl = StringBuffer();
        var opIdx = 0;
        // As in JS, case operations act on UTF-16 code units, not graphemes.
        for (var idx = 0; idx < match.length; idx++) {
          if (opIdx >= caseOps.length) {
            repl.write(match.substring(idx));
            break;
          }
          final character = match.substring(idx, idx + 1);
          switch (caseOps[opIdx]) {
            case 'U':
              repl.write(character.toUpperCase());
            case 'u':
              repl.write(character.toUpperCase());
              opIdx++;
            case 'L':
              repl.write(character.toLowerCase());
            case 'l':
              repl.write(character.toLowerCase());
              opIdx++;
            default:
              repl.write(character);
          }
        }
        match = repl.toString();
      }
      result.write(match);
    }
    return result.toString();
  }

  static String _substitute(int matchIndex, List<String?>? matches) {
    if (matches == null) return '';
    if (matchIndex == 0) return matches[0] ?? '';

    var remainder = '';
    while (matchIndex > 0) {
      if (matchIndex < matches.length) {
        // An unmatched optional capture is undefined in JS and inserts ''.
        return (matches[matchIndex] ?? '') + remainder;
      }
      remainder = '${matchIndex % 10}$remainder';
      matchIndex ~/= 10;
    }
    return '\$$remainder';
  }
}

class _ReplacePieceBuilder {
  _ReplacePieceBuilder(this._source);

  final String _source;
  int _lastCharIndex = 0;
  final List<ReplacePiece> _result = [];
  String _currentStaticPiece = '';

  void emitUnchanged(int toCharIndex) {
    _emitStatic(_source.substring(_lastCharIndex, toCharIndex));
    _lastCharIndex = toCharIndex;
  }

  void emitStatic(String value, int toCharIndex) {
    _emitStatic(value);
    _lastCharIndex = toCharIndex;
  }

  void _emitStatic(String value) {
    if (value.isNotEmpty) _currentStaticPiece += value;
  }

  void emitMatchIndex(int index, int toCharIndex, List<String> caseOps) {
    if (_currentStaticPiece.isNotEmpty) {
      _result.add(ReplacePiece.staticValue(_currentStaticPiece));
      _currentStaticPiece = '';
    }
    _result.add(ReplacePiece.caseOps(index, caseOps));
    _lastCharIndex = toCharIndex;
  }

  ReplacePattern finalize() {
    emitUnchanged(_source.length);
    if (_currentStaticPiece.isNotEmpty) {
      _result.add(ReplacePiece.staticValue(_currentStaticPiece));
      _currentStaticPiece = '';
    }
    return ReplacePattern(_result);
  }
}

/// Parses escapes, case modifiers and `$` capture references from VS Code find.
///
/// `\\n`, `\\t`, `\\\\` insert LF, TAB and backslash; `$$` inserts `$`.
/// `$&`/`$0` insert the full match, `$1` through `$99` reference captures.
/// `\\u`/`\\l` change one character of the next referenced match, whereas
/// `\\U`/`\\L` change all its remaining characters. Unknown escapes are literal.
ReplacePattern parseReplaceString(String replaceString) {
  if (replaceString.isEmpty) return ReplacePattern(null);

  final caseOps = <String>[];
  final result = _ReplacePieceBuilder(replaceString);

  for (var i = 0, len = replaceString.length; i < len; i++) {
    final chCode = replaceString.codeUnitAt(i);
    if (chCode == 0x5c) {
      // Backslash
      i++;
      if (i >= len) break; // A trailing backslash is unchanged.
      final nextChCode = replaceString.codeUnitAt(i);
      switch (nextChCode) {
        case 0x5c: // \\
          result.emitUnchanged(i - 1);
          result.emitStatic('\\', i + 1);
        case 0x6e: // n
          result.emitUnchanged(i - 1);
          result.emitStatic('\n', i + 1);
        case 0x74: // t
          result.emitUnchanged(i - 1);
          result.emitStatic('\t', i + 1);
        case 0x75: // u
        case 0x55: // U
        case 0x6c: // l
        case 0x4c: // L
          result.emitUnchanged(i - 1);
          result.emitStatic('', i + 1);
          caseOps.add(String.fromCharCode(nextChCode));
      }
      continue;
    }

    if (chCode == 0x24) {
      // Dollar sign
      i++;
      if (i >= len) break; // A trailing dollar sign is unchanged.
      final nextChCode = replaceString.codeUnitAt(i);
      if (nextChCode == 0x24) {
        result.emitUnchanged(i - 1);
        result.emitStatic(r'$', i + 1);
        continue;
      }
      if (nextChCode == 0x30 || nextChCode == 0x26) {
        // 0 or &
        result.emitUnchanged(i - 1);
        result.emitMatchIndex(0, i + 1, caseOps);
        caseOps.clear();
        continue;
      }
      if (0x31 <= nextChCode && nextChCode <= 0x39) {
        var matchIndex = nextChCode - 0x30;
        if (i + 1 < len) {
          final nextNextChCode = replaceString.codeUnitAt(i + 1);
          if (0x30 <= nextNextChCode && nextNextChCode <= 0x39) {
            i++;
            matchIndex = matchIndex * 10 + nextNextChCode - 0x30;
            result.emitUnchanged(i - 2);
            result.emitMatchIndex(matchIndex, i + 1, caseOps);
            caseOps.clear();
            continue;
          }
        }
        result.emitUnchanged(i - 1);
        result.emitMatchIndex(matchIndex, i + 1, caseOps);
        caseOps.clear();
      }
    }
  }
  return result.finalize();
}

/// Port of the preserve-case helper imported by upstream replacePattern.ts.
/// Only static replacement patterns use this; dynamic captures ignore the flag.
String buildReplaceStringWithCasePreserved(
  List<String?>? matches,
  String pattern,
) {
  if (matches == null || matches.isEmpty || (matches[0] ?? '').isEmpty) {
    return pattern;
  }
  final match = matches[0]!;
  final containsHyphens = _validateSpecialCharacter(match, pattern, '-');
  final containsUnderscores = _validateSpecialCharacter(match, pattern, '_');
  if (containsHyphens && !containsUnderscores) {
    return _buildForSpecialCharacter(match, pattern, '-');
  } else if (!containsHyphens && containsUnderscores) {
    return _buildForSpecialCharacter(match, pattern, '_');
  }
  if (match.toUpperCase() == match) {
    return pattern.toUpperCase();
  } else if (match.toLowerCase() == match) {
    return pattern.toLowerCase();
  } else if (match.substring(0, 1).toLowerCase() != match.substring(0, 1) &&
      pattern.isNotEmpty) {
    return pattern.substring(0, 1).toUpperCase() + pattern.substring(1);
  } else if (match.substring(0, 1).toUpperCase() != match.substring(0, 1) &&
      pattern.isNotEmpty) {
    return pattern.substring(0, 1).toLowerCase() + pattern.substring(1);
  }
  return pattern;
}

bool _validateSpecialCharacter(
  String match,
  String pattern,
  String separator,
) =>
    match.contains(separator) &&
    pattern.contains(separator) &&
    match.split(separator).length == pattern.split(separator).length;

String _buildForSpecialCharacter(
  String match,
  String pattern,
  String separator,
) {
  final splitPattern = pattern.split(separator);
  final splitMatch = match.split(separator);
  final result = StringBuffer();
  for (var i = 0; i < splitPattern.length; i++) {
    result.write(
      buildReplaceStringWithCasePreserved([splitMatch[i]], splitPattern[i]),
    );
    if (i + 1 < splitPattern.length) result.write(separator);
  }
  return result.toString();
}
