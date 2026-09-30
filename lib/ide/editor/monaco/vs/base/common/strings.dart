/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Subset of VS Code src/vs/base/common/strings.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971 used by glob, path, and the
// language registry: `escapeRegExpCharacters`, `ltrim`, `rtrim`,
// `regExpLeadsToEndlessLoop`, the `compare*`/`equals*`/`*WithIgnoreCase`
// helpers and the UTF-8 BOM helpers. The cursor helpers live in
// strings_cursor.dart.
// Deviations: lower-casing uses [jsToLowerCase] (JavaScript semantics). In
// `compareSubstring`, reading past the end of a string yields "no character"
// like JavaScript's NaN `charCodeAt` (neither less nor greater); the
// ignore-case variant requires ranges inside both strings.
// `regExpLeadsToEndlessLoop` compares `RegExp.pattern` where upstream reads
// `RegExp.source` (they differ only for `/`, line breaks and the empty
// pattern, none of which are among the special cases), and assumes a
// non-global expression, the only kind Dart has.

import 'ecmascript_lower_case.dart';

final RegExp _regExpCharacters = RegExp(r'[\\\{\}\*\+\?\|\^\$\.\[\]\(\)]');

/// Escapes regular expression characters in [value].
String escapeRegExpCharacters(String value) =>
    value.replaceAllMapped(_regExpCharacters, (m) => '\\${m[0]}');

/// Removes all occurrences of [needle] from the beginning of [haystack].
String ltrim(String haystack, String needle) {
  if (haystack.isEmpty || needle.isEmpty) return haystack;
  final needleLen = needle.length;
  var offset = 0;
  if (needleLen == 1) {
    final ch = needle.codeUnitAt(0);
    while (offset < haystack.length && haystack.codeUnitAt(offset) == ch) {
      offset++;
    }
  } else {
    while (haystack.startsWith(needle, offset)) {
      offset += needleLen;
    }
  }
  return haystack.substring(offset);
}

/// Removes all occurrences of [needle] from the end of [haystack].
String rtrim(String haystack, String needle) {
  if (haystack.isEmpty || needle.isEmpty) return haystack;
  final needleLen = needle.length, haystackLen = haystack.length;
  if (needleLen == 1) {
    var end = haystackLen;
    final ch = needle.codeUnitAt(0);
    while (end > 0 && haystack.codeUnitAt(end - 1) == ch) {
      end--;
    }
    return haystack.substring(0, end);
  }
  var offset = haystackLen;
  // JavaScript `endsWith(needle, offset)`.
  while (offset > 0 &&
      offset >= needleLen &&
      haystack.startsWith(needle, offset - needleLen)) {
    offset -= needleLen;
  }
  return haystack.substring(0, offset);
}

bool regExpLeadsToEndlessLoop(RegExp regexp) {
  // Exit early for the special cases meant to match an empty string.
  final source = regexp.pattern;
  if (source == '^' ||
      source == r'^$' ||
      source == r'$' ||
      source == r'^\s*$') {
    return false;
  }
  // If the expression matches the empty string it does not advance.
  return regexp.firstMatch('') != null;
}

int compare(String a, String b) => a.compareTo(b).sign;

/// `charCodeAt`, with JavaScript's NaN for an index outside the string.
num _charCodeAt(String s, int index) =>
    index >= 0 && index < s.length ? s.codeUnitAt(index) : double.nan;

int compareSubstring(
  String a,
  String b, [
  int aStart = 0,
  int? aEnd,
  int bStart = 0,
  int? bEnd,
]) {
  aEnd ??= a.length;
  bEnd ??= b.length;
  for (; aStart < aEnd && bStart < bEnd; aStart++, bStart++) {
    final codeA = _charCodeAt(a, aStart);
    final codeB = _charCodeAt(b, bStart);
    if (codeA < codeB) {
      return -1;
    } else if (codeA > codeB) {
      return 1;
    }
  }
  final aLen = aEnd - aStart;
  final bLen = bEnd - bStart;
  if (aLen < bLen) {
    return -1;
  } else if (aLen > bLen) {
    return 1;
  }
  return 0;
}

int compareIgnoreCase(String a, String b) =>
    compareSubstringIgnoreCase(a, b, 0, a.length, 0, b.length);

int compareSubstringIgnoreCase(
  String a,
  String b, [
  int aStart = 0,
  int? aEnd,
  int bStart = 0,
  int? bEnd,
]) {
  aEnd ??= a.length;
  bEnd ??= b.length;
  for (; aStart < aEnd && bStart < bEnd; aStart++, bStart++) {
    var codeA = a.codeUnitAt(aStart);
    var codeB = b.codeUnitAt(bStart);
    if (codeA == codeB) {
      continue;
    }
    if (codeA >= 128 || codeB >= 128) {
      // Not ASCII letters: fall back to lower-casing the strings (keeping
      // the original offsets, as upstream does).
      return compareSubstring(
        jsToLowerCase(a),
        jsToLowerCase(b),
        aStart,
        aEnd,
        bStart,
        bEnd,
      );
    }
    // Map lower-case ASCII letters onto their upper-case variants.
    if (isLowerAsciiLetter(codeA)) codeA -= 32;
    if (isLowerAsciiLetter(codeB)) codeB -= 32;
    final diff = codeA - codeB;
    if (diff == 0) {
      continue;
    }
    return diff;
  }
  final aLen = aEnd - aStart;
  final bLen = bEnd - bStart;
  if (aLen < bLen) {
    return -1;
  } else if (aLen > bLen) {
    return 1;
  }
  return 0;
}

bool isLowerAsciiLetter(int code) => code >= 0x61 && code <= 0x7A;

bool isUpperAsciiLetter(int code) => code >= 0x41 && code <= 0x5A;

bool equalsIgnoreCase(String a, String b) =>
    a.length == b.length && compareSubstringIgnoreCase(a, b) == 0;

bool equals(String? a, String? b, [bool ignoreCase = false]) =>
    a == b || (ignoreCase && a != null && b != null && equalsIgnoreCase(a, b));

bool startsWithIgnoreCase(String str, String candidate) {
  final len = candidate.length;
  return len <= str.length &&
      compareSubstringIgnoreCase(str, candidate, 0, len) == 0;
}

bool endsWithIgnoreCase(String str, String candidate) {
  final len = str.length;
  final start = len - candidate.length;
  return start >= 0 &&
      compareSubstringIgnoreCase(str, candidate, start, len) == 0;
}

/// Upstream `UTF8_BOM_CHARACTER`.
const String utf8BomCharacter = '\uFEFF';

bool startsWithUTF8BOM(String? str) =>
    str != null && str.isNotEmpty && str.codeUnitAt(0) == 0xFEFF;

String stripUTF8BOM(String str) =>
    startsWithUTF8BOM(str) ? str.substring(1) : str;
