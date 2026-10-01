/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Port of VS Code src/vs/base/common/glob.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971: patterns, relative patterns and
// expressions (with sibling clauses), the trivial-pattern fast paths, the
// bounded parse cache, basename/path terms, `patternsEquals` and
// `isEmptyPattern`.
// Dart API adaptations: upstream's overloaded `parse`/`match` are split into
// [parse]/[match] for a pattern (a `String` or an [IRelativePattern]) and
// [parseExpression]/[matchExpression] for an [IExpression]. TypeScript's
// callable functions with properties are the [ParsedPattern] and
// [ParsedExpression] classes. A promise is a `Future`; `FutureOr` results
// replace `string | null | Promise<string | null>`. `matchExpression` returns
// `null` where upstream returns `false` for a missing path. Expression keys are
// visited in JavaScript property order (array-index keys first, ascending).
// The cache is a small LRU map with upstream's bound (10000 entries) and is
// cleared when platform.dart's operating system changes, because parsed
// patterns capture the path separator.

import 'dart:async';

import 'ecmascript_lower_case.dart';
import 'extpath.dart';
import 'path.dart' as paths;
import 'platform.dart';
import 'strings.dart';

/// A glob matched relative to [base].
class IRelativePattern {
  const IRelativePattern({required this.base, required this.pattern});

  /// A base file path to which [pattern] is matched relatively.
  final String base;

  /// A file glob pattern like `*.{ts,js}` matched on file paths relative to
  /// [base].
  final String pattern;
}

/// Upstream `SiblingClause`: `{ "when": "$(basename).ts" }`.
class SiblingClause {
  const SiblingClause({required this.when});

  final String when;
}

/// Upstream `IExpression`: glob pattern to `true`/`false` or a
/// [SiblingClause]. Like upstream, `false` disables a pattern and any other
/// value (a `Map` with a string `when` counts as a clause) enables it.
typedef IExpression = Map<String, Object?>;

IExpression getEmptyExpression() => <String, Object?>{};

/// Upstream `hasSibling`.
typedef SiblingPredicate = FutureOr<bool> Function(String name);

const String globstar = '**';
const String globSplit = '/';

const String _pathRegex = r'[/\\]'; // any slash or backslash
const String _noPathRegex = r'[^/\\]'; // any non-slash and non-backslash

String _starsToRegExp(int starCount, [bool isLastPattern = false]) {
  switch (starCount) {
    case 0:
      return '';
    case 1:
      // Any number of characters except path separators, non-greedy.
      return '$_noPathRegex*?';
    default:
      // (Path Sep OR Path Val followed by Path Sep) 0-many times, except when
      // it is the last pattern, which also matches (Path Sep followed by Path
      // Val). Non-capturing and non-greedy.
      return '(?:$_pathRegex|$_noPathRegex+$_pathRegex'
          '${isLastPattern ? '|$_pathRegex$_noPathRegex+' : ''})*?';
  }
}

List<String> splitGlobAware(String? pattern, String splitChar) {
  if (pattern == null || pattern.isEmpty) return [];
  final segments = <String>[];
  var inBraces = false;
  var inBrackets = false;
  var curVal = StringBuffer();
  for (final char in _codePointStrings(pattern)) {
    if (char == splitChar) {
      if (!inBraces && !inBrackets) {
        segments.add(curVal.toString());
        curVal = StringBuffer();
        continue;
      }
    } else if (char == '{') {
      inBraces = true;
    } else if (char == '}') {
      inBraces = false;
    } else if (char == '[') {
      inBrackets = true;
    } else if (char == ']') {
      inBrackets = false;
    }
    curVal.write(char);
  }
  // Tail
  if (curVal.isNotEmpty) segments.add(curVal.toString());
  return segments;
}

/// `for (const char of string)`: iterates by code point.
Iterable<String> _codePointStrings(String s) =>
    s.runes.map(String.fromCharCode);

String _parseRegExp(String pattern) {
  if (pattern.isEmpty) return '';
  final regEx = StringBuffer();

  // Split up into segments for each slash found.
  final segments = splitGlobAware(pattern, globSplit);

  if (segments.every((segment) => segment == globstar)) {
    // Special case where we only have globstars.
    regEx.write('.*');
  } else {
    var previousSegmentWasGlobStar = false;
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      if (segment == globstar) {
        // If we have more than one globstar after another, just ignore it.
        if (!previousSegmentWasGlobStar) {
          regEx.write(_starsToRegExp(2, index == segments.length - 1));
        }
      } else {
        var inBraces = false;
        var braceVal = StringBuffer();
        var inBrackets = false;
        var bracketVal = StringBuffer();

        for (final char in _codePointStrings(segment)) {
          // Support brace expansion.
          if (char != '}' && inBraces) {
            braceVal.write(char);
            continue;
          }

          // Support brackets; `]` is only literal as the first character.
          if (inBrackets && (char != ']' || bracketVal.isEmpty)) {
            String res;
            if (char == '-') {
              // Range operator.
              res = char;
            } else if ((char == '^' || char == '!') && bracketVal.isEmpty) {
              // Negation operator (only valid on first index in bracket).
              res = '^';
            } else if (char == globSplit) {
              // Glob split matching is not allowed within character ranges,
              // see http://man7.org/linux/man-pages/man7/glob.7.html
              res = '';
            } else {
              // Anything else gets escaped.
              res = escapeRegExpCharacters(char);
            }
            bracketVal.write(res);
            continue;
          }

          switch (char) {
            case '{':
              inBraces = true;
              continue;
            case '[':
              inBrackets = true;
              continue;
            case '}':
              final choices = splitGlobAware(braceVal.toString(), ',');
              // Converts {foo,bar} => [foo|bar]
              regEx.write('(?:${choices.map(_parseRegExp).join('|')})');
              inBraces = false;
              braceVal = StringBuffer();
            case ']':
              regEx.write('[$bracketVal]');
              inBrackets = false;
              bracketVal = StringBuffer();
            case '?':
              // One character except path separators.
              regEx.write(_noPathRegex);
              continue;
            case '*':
              regEx.write(_starsToRegExp(1));
              continue;
            default:
              regEx.write(escapeRegExpCharacters(char));
          }
        }

        // Tail: add the slash we split on if there is more to come and the
        // remaining pattern is not a globstar. For `some/**/*.js` the `/`
        // after `some` keeps a folder called `something` from matching.
        if (index < segments.length - 1 &&
            (segments[index + 1] != globstar || index + 2 < segments.length)) {
          regEx.write(_pathRegex);
        }
      }

      // Update globstar state.
      previousSegmentWasGlobStar = segment == globstar;
    }
  }
  return regEx.toString();
}

// Trivial glob patterns that just check for String#endsWith.
final RegExp _t1 = RegExp(r'^\*\*\/\*\.[\w\.-]+$'); // **/*.something
final RegExp _t2 = RegExp(r'^\*\*\/([\w\.-]+)\/?$'); // **/something
// {**/*.something,**/*.else} or {**/package.json,**/project.json}
final RegExp _t3 = RegExp(r'^{\*\*\/\*?[\w\.-]+\/?(,\*\*\/\*?[\w\.-]+\/?)*}$');
// Like T3, with optional trailing /**
final RegExp _t3_2 = RegExp(
  r'^{\*\*\/\*?[\w\.-]+(\/(\*\*)?)?(,\*\*\/\*?[\w\.-]+(\/(\*\*)?)?)*}$',
);
final RegExp _t4 = RegExp(r'^\*\*((\/[\w\.-]+)+)\/?$'); // **/something/else
final RegExp _t5 = RegExp(r'^([\w\.-]+(\/[\w\.-]+)*)\/?$'); // something/else

class IGlobOptions {
  const IGlobOptions({this.trimForExclusions, this.ignoreCase});

  /// Simplify patterns for use as exclusion filters during tree traversal to
  /// skip entire subtrees. Cannot be used outside of a tree traversal.
  final bool? trimForExclusions;

  /// Whether glob pattern matching should be case insensitive.
  final bool? ignoreCase;
}

class _GlobOptionsInternal extends IGlobOptions {
  const _GlobOptionsInternal({
    super.trimForExclusions,
    super.ignoreCase,
    required this.equals,
    required this.endsWith,
    required this.isEqualOrParent,
  });

  final bool Function(String a, String b) equals;
  final bool Function(String str, String candidate) endsWith;
  final bool Function(String base, String candidate) isEqualOrParent;
}

typedef _PatternFunction = FutureOr<String?> Function(
  String? path,
  String? basename,
  String? name,
  SiblingPredicate? hasSibling,
);

/// Upstream `ParsedStringPattern` / `ParsedExpressionPattern`: returns the
/// matching pattern or `null`.
class _Parsed {
  _Parsed(this._fn);

  final _PatternFunction _fn;
  List<String>? basenames;
  List<String>? patterns;
  List<String>? allBasenames;
  List<String>? allPaths;
  bool requiresSiblings = false;

  FutureOr<String?> call(
    String? path, [
    String? basename,
    String? name,
    SiblingPredicate? hasSibling,
  ]) => _fn(path, basename, name, hasSibling);
}

final _Parsed _null = _Parsed((_, _, _, _) => null);

/// A parsed pattern: `call(path, [basename])` tells whether it matches.
final class ParsedPattern {
  ParsedPattern._(this._fn, {this.allBasenames, this.allPaths});

  static final ParsedPattern _false = ParsedPattern._((_, _) => false);

  final bool Function(String? path, String? basename) _fn;
  final List<String>? allBasenames;
  final List<String>? allPaths;

  bool call(String? path, [String? basename]) => _fn(path, basename);
}

/// A parsed expression: `call(path, [basename, hasSibling])` returns the
/// matching pattern or `null` (a `Future` iff [SiblingPredicate] does).
final class ParsedExpression {
  ParsedExpression._(this._parsed, [this._siblingAware = false]);

  final _Parsed _parsed;
  // Whether the underlying function takes `hasSibling` as its third
  // argument (the sibling-aware expression) or ignores it.
  final bool _siblingAware;

  List<String>? get allBasenames => _parsed.allBasenames;
  List<String>? get allPaths => _parsed.allPaths;

  FutureOr<String?> call(
    String? path, [
    String? basename,
    SiblingPredicate? hasSibling,
  ]) => _siblingAware
      ? _parsed(path, basename, null, hasSibling)
      : _parsed(path, basename);
}

/// A tiny LRU map standing in for upstream's `LRUCache` (map.ts): reads and
/// writes make an entry the most recent; the oldest go beyond [_limit].
class _LRUCache<K, V> {
  _LRUCache(this._limit);

  final int _limit;
  final Map<K, V> _map = {};

  V? get(K key) {
    final value = _map.remove(key);
    if (value != null) _map[key] = value;
    return value;
  }

  void set(K key, V value) {
    _map.remove(key);
    _map[key] = value;
    while (_map.length > _limit) {
      _map.remove(_map.keys.first);
    }
  }

  void clear() => _map.clear();
}

final _LRUCache<String, _Parsed> _cache = _LRUCache(10000);
OperatingSystem? _cacheOs;

/// Whether [pattern] (from [parse] or [parseExpression]) can never match.
bool isEmptyPattern(Object pattern) =>
    identical(pattern, ParsedPattern._false) ||
    (pattern is ParsedExpression && identical(pattern._parsed, _null));

_Parsed _parsePattern(Object arg1, IGlobOptions options, [String? cacheKey]) {
  // Handle relative patterns.
  var pattern = arg1 is IRelativePattern ? arg1.pattern : arg1 as String;
  if (pattern.isEmpty && arg1 is String) return _null;

  // Whitespace trimming (JavaScript trim).
  pattern = _jsTrim(pattern);

  final ignoreCase = options.ignoreCase ?? false;
  final internalOptions = _GlobOptionsInternal(
    trimForExclusions: options.trimForExclusions,
    ignoreCase: options.ignoreCase,
    equals: ignoreCase ? equalsIgnoreCase : (a, b) => a == b,
    endsWith: ignoreCase
        ? endsWithIgnoreCase
        : (str, candidate) => str.endsWith(candidate),
    // Preserve old behaviour for when the option is not adopted.
    isEqualOrParent: (base, candidate) =>
        isEqualOrParent(base, candidate, options.ignoreCase ?? !isLinux),
  );

  if (_cacheOs != os) {
    _cache.clear();
    _cacheOs = os;
  }

  // Check cache.
  final patternKey =
      '${cacheKey == null ? 'default:${ignoreCase ? jsToLowerCase(pattern) : pattern}' : 'custom:$cacheKey'}'
      '_${options.trimForExclusions == true}_$ignoreCase';
  var parsedPattern = _cache.get(patternKey);
  if (parsedPattern != null) {
    return _wrapRelativePattern(parsedPattern, arg1, internalOptions);
  }

  // Check for trivials.
  RegExpMatch? match;
  if (_t1.hasMatch(pattern)) {
    // Common pattern: **/*.txt just needs an endsWith check.
    parsedPattern = _trivia1(pattern.substring(4), pattern, internalOptions);
  } else if ((match = _t2.firstMatch(
        _trimForExclusions(pattern, internalOptions),
      )) !=
      null) {
    // Common pattern: **/some.txt just needs a basename check.
    parsedPattern = _trivia2(match![1]!, pattern, internalOptions);
  } else if ((options.trimForExclusions == true ? _t3_2 : _t3).hasMatch(
    pattern,
  )) {
    // Repetition of common patterns (see above) {**/*.txt,**/*.png}.
    parsedPattern = _trivia3(pattern, internalOptions);
  } else if ((match = _t4.firstMatch(
        _trimForExclusions(pattern, internalOptions),
      )) !=
      null) {
    // Common pattern: **/something/else just needs an endsWith check.
    parsedPattern = _trivia4and5(
      match![1]!.substring(1),
      pattern,
      true,
      internalOptions,
    );
  } else if ((match = _t5.firstMatch(
        _trimForExclusions(pattern, internalOptions),
      )) !=
      null) {
    // Common pattern: something/else just needs an equals check.
    parsedPattern = _trivia4and5(match![1]!, pattern, false, internalOptions);
  } else {
    // Otherwise convert to a regular expression.
    parsedPattern = _toRegExp(pattern, internalOptions);
  }

  _cache.set(patternKey, parsedPattern);
  return _wrapRelativePattern(parsedPattern, arg1, internalOptions);
}

// JavaScript's String.prototype.trim: `\s` is WhiteSpace and LineTerminator
// in both engines (Dart's `String.trim` also strips U+0085).
final RegExp _jsTrimPattern = RegExp(r'^\s+|\s+$');

String _jsTrim(String s) => s.replaceAll(_jsTrimPattern, '');

_Parsed _wrapRelativePattern(
  _Parsed parsedPattern,
  Object arg2,
  _GlobOptionsInternal options,
) {
  if (arg2 is! IRelativePattern) return parsedPattern;

  final wrappedPattern = _Parsed((path, basename, _, _) {
    if (path == null || !options.isEqualOrParent(path, arg2.base)) {
      // Skip glob matching if `base` is not a parent of `path`.
      return null;
    }
    // `base` is a parent of `path`: match only the remaining components.
    // `base` might end in a path separator (#162498).
    return parsedPattern(
      ltrim(path.substring(arg2.base.length), paths.sep),
      basename,
    );
  });

  // Make sure to preserve associated metadata.
  wrappedPattern.allBasenames = parsedPattern.allBasenames;
  wrappedPattern.allPaths = parsedPattern.allPaths;
  wrappedPattern.basenames = parsedPattern.basenames;
  wrappedPattern.patterns = parsedPattern.patterns;
  return wrappedPattern;
}

String _trimForExclusions(String pattern, IGlobOptions options) =>
    options.trimForExclusions == true && pattern.endsWith('/**')
    ? pattern.substring(0, pattern.length - 2)
    : pattern; // dropping **, tailing / is dropped later

// Common pattern: **/*.txt just needs an endsWith check.
_Parsed _trivia1(String base, String pattern, _GlobOptionsInternal options) =>
    _Parsed(
      (path, basename, _, _) =>
          path != null && options.endsWith(path, base) ? pattern : null,
    );

// Common pattern: **/some.txt just needs a basename check.
_Parsed _trivia2(String base, String pattern, _GlobOptionsInternal options) {
  final slashBase = '/$base';
  final backslashBase = '\\$base';
  final parsedPattern = _Parsed((path, basename, _, _) {
    if (path == null) return null;
    if (basename != null && basename.isNotEmpty) {
      return options.equals(basename, base) ? pattern : null;
    }
    return options.equals(path, base) ||
            options.endsWith(path, slashBase) ||
            options.endsWith(path, backslashBase)
        ? pattern
        : null;
  });
  final basenames = [base];
  parsedPattern.basenames = basenames;
  parsedPattern.patterns = [pattern];
  parsedPattern.allBasenames = basenames;
  return parsedPattern;
}

// Repetition of common patterns (see above) {**/*.txt,**/*.png}.
_Parsed _trivia3(String pattern, _GlobOptionsInternal options) {
  final parsedPatterns = _aggregateBasenameMatches(
    pattern
        .substring(1, pattern.length - 1)
        .split(',')
        .map((pattern) => _parsePattern(pattern, options))
        .where((pattern) => !identical(pattern, _null))
        .toList(),
    pattern,
    options.ignoreCase,
  );
  final patternsLength = parsedPatterns.length;
  if (patternsLength == 0) return _null;
  if (patternsLength == 1) return parsedPatterns[0];

  final parsedPattern = _Parsed((path, basename, _, _) {
    for (var i = 0, n = parsedPatterns.length; i < n; i++) {
      // Sub-patterns are all synchronous here.
      if (parsedPatterns[i](path, basename) != null) return pattern;
    }
    return null;
  });

  final withBasenames = parsedPatterns
      .where((pattern) => pattern.allBasenames != null)
      .firstOrNull;
  if (withBasenames != null) {
    parsedPattern.allBasenames = withBasenames.allBasenames;
  }
  final allPaths = [for (final p in parsedPatterns) ...?p.allPaths];
  if (allPaths.isNotEmpty) parsedPattern.allPaths = allPaths;
  return parsedPattern;
}

// Common patterns: **/something/else just needs an endsWith check,
// something/else just needs an equals check.
_Parsed _trivia4and5(
  String targetPath,
  String pattern,
  bool matchPathEnds,
  _GlobOptionsInternal options,
) {
  final sep = paths.sep;
  final usingPosixSep = sep == paths.posix.sep;
  final nativePath = usingPosixSep
      ? targetPath
      : targetPath.replaceAll('/', sep);
  final nativePathEnd = sep + nativePath;
  final targetPathEnd = paths.posix.sep + targetPath;

  final _Parsed parsedPattern;
  if (matchPathEnds) {
    parsedPattern = _Parsed(
      (path, basename, _, _) =>
          path != null &&
              ((options.equals(path, nativePath) ||
                      options.endsWith(path, nativePathEnd)) ||
                  !usingPosixSep &&
                      (options.equals(path, targetPath) ||
                          options.endsWith(path, targetPathEnd)))
          ? pattern
          : null,
    );
  } else {
    parsedPattern = _Parsed(
      (path, basename, _, _) =>
          path != null &&
              (options.equals(path, nativePath) ||
                  (!usingPosixSep && options.equals(path, targetPath)))
          ? pattern
          : null,
    );
  }
  parsedPattern.allPaths = ['${matchPathEnds ? '*/' : './'}$targetPath'];
  return parsedPattern;
}

_Parsed _toRegExp(String pattern, IGlobOptions options) {
  final RegExp regExp;
  try {
    regExp = RegExp(
      '^${_parseRegExp(pattern)}\$',
      caseSensitive: options.ignoreCase != true,
    );
  } on FormatException {
    return _null;
  }
  return _Parsed(
    (path, basename, _, _) =>
        path != null && regExp.hasMatch(path) ? pattern : null,
  );
}

/// Simplified glob matching. Supports a subset of glob patterns:
/// * `*` to match zero or more characters in a path segment
/// * `?` to match on one character in a path segment
/// * `**` to match any number of path segments, including none
/// * `{}` to group conditions (e.g. `*.{ts,js}` matches all TypeScript and
///   JavaScript files)
/// * `[]` to declare a range of characters to match in a path segment (e.g.,
///   `example.[0-9]` to match on `example.0`, `example.1`, …)
/// * `[!...]` to negate a range of characters to match in a path segment
///   (e.g., `example.[!0-9]` to match on `example.a`, `example.b`, but not
///   `example.0`)
///
/// [pattern] is a `String`, an [IRelativePattern] or `null`.
bool match(
  Object? pattern,
  String? path, [
  IGlobOptions options = const IGlobOptions(),
]) {
  if (pattern == null || (pattern is String && pattern.isEmpty)) return false;
  if (path == null) return false;
  return parse(pattern, options)(path);
}

/// Matches [path] against [expression]; returns the matching pattern.
String? matchExpression(
  IExpression? expression,
  String? path, [
  IGlobOptions options = const IGlobOptions(),
]) {
  if (expression == null || path == null) return null;
  // Without a sibling predicate the result is synchronous.
  return parseExpression(expression, options)(path) as String?;
}

/// Parses a glob [pattern] (a `String`, an [IRelativePattern] or `null`); see
/// [match] for the syntax.
ParsedPattern parse(
  Object? pattern, [
  IGlobOptions options = const IGlobOptions(),
]) {
  if (pattern == null || (pattern is String && pattern.isEmpty)) {
    return ParsedPattern._false;
  }
  if (pattern is! String && pattern is! IRelativePattern) {
    throw ArgumentError.value(pattern, 'pattern', 'not a glob pattern');
  }
  final parsedPattern = _parsePattern(pattern, options);
  if (identical(parsedPattern, _null)) return ParsedPattern._false;
  return ParsedPattern._(
    (path, basename) => parsedPattern(path, basename) != null,
    allBasenames: parsedPattern.allBasenames,
    allPaths: parsedPattern.allPaths,
  );
}

/// Parses a glob [expression]; see [match] for the syntax.
ParsedExpression parseExpression(
  IExpression expression, [
  IGlobOptions options = const IGlobOptions(),
]) => _parsedExpression(expression, options);

bool isRelativePattern(Object? obj) => obj is IRelativePattern;

List<String> getBasenameTerms(Object patternOrExpression) =>
    switch (patternOrExpression) {
      ParsedPattern p => p.allBasenames,
      ParsedExpression e => e.allBasenames,
      _ => null,
    } ??
    [];

List<String> getPathTerms(Object patternOrExpression) =>
    switch (patternOrExpression) {
      ParsedPattern p => p.allPaths,
      ParsedExpression e => e.allPaths,
      _ => null,
    } ??
    [];

// `Object.getOwnPropertyNames` order: array-index keys ascending, then the
// others in insertion order.
List<String> _ownPropertyNames(Map<String, Object?> object) {
  final indices = <String>[], others = <String>[];
  for (final key in object.keys) {
    (_isArrayIndex(key) ? indices : others).add(key);
  }
  indices.sort((a, b) => int.parse(a).compareTo(int.parse(b)));
  return [...indices, ...others];
}

bool _isArrayIndex(String key) {
  if (key.isEmpty || key.length > 10) return false;
  if (key.length > 1 && key.startsWith('0')) return false;
  for (final unit in key.codeUnits) {
    if (unit < 0x30 || unit > 0x39) return false;
  }
  return int.parse(key) < 0xFFFFFFFF;
}

ParsedExpression _parsedExpression(
  IExpression expression,
  IGlobOptions options,
) {
  final parsedPatterns = _aggregateBasenameMatches(
    _ownPropertyNames(expression)
        .map(
          (pattern) =>
              _parseExpressionPattern(pattern, expression[pattern], options),
        )
        .where((pattern) => !identical(pattern, _null))
        .toList(),
    null,
    options.ignoreCase,
  );

  final patternsLength = parsedPatterns.length;
  if (patternsLength == 0) return ParsedExpression._(_null);

  if (!parsedPatterns.any((parsedPattern) => parsedPattern.requiresSiblings)) {
    if (patternsLength == 1) return ParsedExpression._(parsedPatterns[0]);

    final resultExpression = _Parsed((path, basename, _, _) {
      List<Future<String?>>? resultPromises;
      for (var i = 0, n = parsedPatterns.length; i < n; i++) {
        final result = parsedPatterns[i](path, basename);
        if (result is String) {
          return result; // the first matching expression wins
        }
        // Keep promises to await them before returning.
        if (result is Future<String?>) (resultPromises ??= []).add(result);
      }
      if (resultPromises != null) {
        final promises = resultPromises;
        return () async {
          for (final resultPromise in promises) {
            final result = await resultPromise;
            if (result != null) return result;
          }
          return null;
        }();
      }
      return null;
    });
    _copyTerms(resultExpression, parsedPatterns);
    return ParsedExpression._(resultExpression);
  }

  final resultExpression = _Parsed((path, base, _, hasSibling) {
    String? name;
    List<Future<String?>>? resultPromises;
    for (var i = 0, n = parsedPatterns.length; i < n; i++) {
      // Pattern matches path.
      final parsedPattern = parsedPatterns[i];
      if (parsedPattern.requiresSiblings && hasSibling != null) {
        final String current;
        if (base == null || base.isEmpty) {
          current = base = paths.basename(path!);
        } else {
          current = base;
        }
        name ??= current.substring(
          0,
          current.length - paths.extname(path!).length,
        );
      }
      final result = parsedPattern(path, base, name, hasSibling);
      if (result is String) {
        return result; // the first matching expression wins
      }
      // Keep promises to await them before returning.
      if (result is Future<String?>) (resultPromises ??= []).add(result);
    }
    if (resultPromises != null) {
      final promises = resultPromises;
      return () async {
        for (final resultPromise in promises) {
          final result = await resultPromise;
          if (result != null) return result;
        }
        return null;
      }();
    }
    return null;
  });
  _copyTerms(resultExpression, parsedPatterns);
  return ParsedExpression._(resultExpression, true);
}

void _copyTerms(_Parsed result, List<_Parsed> parsedPatterns) {
  final withBasenames = parsedPatterns
      .where((pattern) => pattern.allBasenames != null)
      .firstOrNull;
  if (withBasenames != null) result.allBasenames = withBasenames.allBasenames;
  final allPaths = [for (final p in parsedPatterns) ...?p.allPaths];
  if (allPaths.isNotEmpty) result.allPaths = allPaths;
}

_Parsed _parseExpressionPattern(
  String pattern,
  Object? value,
  IGlobOptions options,
) {
  if (value == false) return _null; // pattern is disabled

  final parsedPattern = _parsePattern(pattern, options, pattern);
  if (identical(parsedPattern, _null)) return _null;

  // Expression pattern is a boolean.
  if (value is bool) return parsedPattern;

  // Expression pattern is a sibling clause.
  final when = switch (value) {
    SiblingClause(when: final clause) => clause,
    Map() => value['when'],
    _ => null,
  };
  if (when is String) {
    final result = _Parsed((path, basename, name, hasSibling) {
      if (hasSibling == null || parsedPattern(path, basename) == null) {
        return null;
      }
      final clausePattern = when.replaceFirst('\$(basename)', name!);
      final matched = hasSibling(clausePattern);
      return matched is Future<bool>
          ? matched.then((match) => match ? pattern : null)
          : matched
          ? pattern
          : null;
    });
    result.requiresSiblings = true;
    return result;
  }

  // Expression is anything.
  return parsedPattern;
}

List<_Parsed> _aggregateBasenameMatches(
  List<_Parsed> parsedPatterns,
  String? result,
  bool? ignoreCase,
) {
  final basenamePatterns = parsedPatterns
      .where((parsedPattern) => parsedPattern.basenames != null)
      .toList();
  if (basenamePatterns.length < 2) return parsedPatterns;

  final basenames = [for (final p in basenamePatterns) ...?p.basenames];
  final List<String> patterns;
  if (result != null) {
    patterns = [for (var i = 0; i < basenames.length; i++) result];
  } else {
    patterns = [for (final p in basenamePatterns) ...?p.patterns];
  }

  final aggregate = _Parsed((path, basename, _, _) {
    if (path == null) return null;
    var name = basename;
    if (name == null || name.isEmpty) {
      int i;
      for (i = path.length; i > 0; i--) {
        final ch = path.codeUnitAt(i - 1);
        if (ch == 0x2F || ch == 0x5C) break;
      }
      name = path.substring(i);
    }
    final target = name;
    final index = ignoreCase == true
        ? basenames.indexWhere(
            (candidate) => equalsIgnoreCase(candidate, target),
          )
        : basenames.indexOf(target);
    return index != -1 ? patterns[index] : null;
  });
  aggregate.basenames = basenames;
  aggregate.patterns = patterns;
  aggregate.allBasenames = basenames;

  return [
    ...parsedPatterns.where((parsedPattern) => parsedPattern.basenames == null),
    aggregate,
  ];
}

/// Whether two pattern lists are equal. Only used to reset watchers when
/// patterns change, so the comparison is case-sensitive.
bool patternsEquals(List<Object>? patternsA, List<Object>? patternsB) {
  if (identical(patternsA, patternsB)) return true;
  if (patternsA == null || patternsB == null) return false;
  if (patternsA.length != patternsB.length) return false;
  for (var i = 0; i < patternsA.length; i++) {
    final a = patternsA[i], b = patternsB[i];
    final bool same;
    if (a is String && b is String) {
      same = a == b;
    } else if (a is IRelativePattern && b is IRelativePattern) {
      same = a.base == b.base && a.pattern == b.pattern;
    } else {
      same = false;
    }
    if (!same) return false;
  }
  return true;
}
