/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// JavaScript's semantics for the operations context key expressions do on
// their values (`==`, `<`, `String(v)`, `parseFloat`, `!!v`, `RegExp`), so
// a `when` clause evaluates here as it does in VS Code.
//
// Deviations: Dart's `null` stands for both `null` and `undefined`; it
// converts to the string `undefined` (a missing context key is the usual
// case).

/// JavaScript's `!!value`.
bool jsTruthy(Object? value) => switch (value) {
  null || false => false,
  final String s => s.isNotEmpty,
  final num n => n != 0 && !n.isNaN,
  _ => true,
};

/// JavaScript's `String(value)`.
String jsToString(Object? value) => switch (value) {
  null => 'undefined',
  final bool b => '$b',
  final String s => s,
  final num n => jsNumberToString(n),
  final List<Object?> list =>
    list.map((e) => e == null ? '' : jsToString(e)).join(','),
  final Map<Object?, Object?> _ => '[object Object]',
  _ => value.toString(),
};

/// `Number.prototype.toString()`.
String jsNumberToString(num n) {
  if (n is int) return '$n';
  final d = n.toDouble();
  if (d.isNaN) return 'NaN';
  if (d.isInfinite) return d > 0 ? 'Infinity' : '-Infinity';
  if (d == d.truncateToDouble() && d.abs() < 1e21) return '${d.toInt()}';
  return d.toString();
}

final _numberLiteral = RegExp(
  r'^[+-]?(Infinity|(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?)$',
);
final _hexLiteral = RegExp(r'^0[xX][0-9a-fA-F]+$');
final _floatPrefix = RegExp(
  r'^[+-]?(Infinity|(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?)',
);

double _parseNumberText(String text) {
  if (text.endsWith('Infinity')) {
    return text.startsWith('-') ? double.negativeInfinity : double.infinity;
  }
  return double.parse(text);
}

/// JavaScript's `Number(value)` (`ToNumber`).
double jsToNumber(Object? value) {
  switch (value) {
    case null:
      return double.nan;
    case final bool b:
      return b ? 1 : 0;
    case final num n:
      return n.toDouble();
    case final String s:
      final t = s.trim();
      if (t.isEmpty) return 0;
      if (_hexLiteral.hasMatch(t)) {
        return int.parse(t.substring(2), radix: 16).toDouble();
      }
      if (_numberLiteral.hasMatch(t)) return _parseNumberText(t);
      return double.nan;
    case final List<Object?> _:
      return jsToNumber(jsToString(value));
    default:
      return double.nan;
  }
}

/// JavaScript's `parseFloat(value)`.
double jsParseFloat(Object? value) {
  final text = jsToString(value).trimLeft();
  final match = _floatPrefix.firstMatch(text);
  if (match == null) return double.nan;
  return _parseNumberText(match[0]!);
}

bool _isPrimitive(Object? v) =>
    v == null || v is bool || v is num || v is String;

/// JavaScript's `a == b` (loose equality).
bool jsLooseEquals(Object? a, Object? b) {
  if (a == null || b == null) return a == null && b == null;
  if (a is String && b is String) return a == b;
  if (a is num && b is num) return a == b && !a.isNaN;
  if (a is bool && b is bool) return a == b;
  if (!_isPrimitive(a) && !_isPrimitive(b)) return identical(a, b);
  if (a is bool) return jsLooseEquals(a ? 1 : 0, b);
  if (b is bool) return jsLooseEquals(a, b ? 1 : 0);
  if (a is num && b is String) return a == jsToNumber(b);
  if (a is String && b is num) return jsToNumber(a) == b;
  // An object against a primitive: the object's primitive (its string).
  if (!_isPrimitive(a)) return jsLooseEquals(jsToString(a), b);
  if (!_isPrimitive(b)) return jsLooseEquals(a, jsToString(b));
  return false;
}

/// JavaScript's `a === b` for the values context keys hold.
bool jsStrictEquals(Object? a, Object? b) {
  if (a is num && b is num) return a == b && !a.isNaN;
  if (a is String || a is bool || a == null) return a == b;
  return identical(a, b);
}

/// JavaScript's `a < b`.
bool jsLessThan(Object? a, Object? b) {
  if (a is String && b is String) return a.compareTo(b) < 0;
  final x = jsToNumber(_isPrimitive(a) ? a : jsToString(a));
  final y = jsToNumber(_isPrimitive(b) ? b : jsToString(b));
  if (x.isNaN || y.isNaN) return false;
  return x < y;
}

/// A JavaScript regular expression: its normalized [source] and [flags] as
/// JavaScript reports them, and the Dart [RegExp] that matches the same.
final class JsRegExp {
  JsRegExp._(this.source, this.flags, this.regExp);

  /// `new RegExp(pattern, flags)`; throws a [FormatException] where
  /// JavaScript throws a `SyntaxError`.
  factory JsRegExp(String pattern, [String flags = '']) {
    const known = 'dgimsuvy';
    final seen = <String>{};
    for (final f in flags.split('')) {
      if (!known.contains(f) || !seen.add(f)) {
        throw FormatException(
          "Invalid flags supplied to RegExp constructor '$flags'",
        );
      }
    }
    final regExp = RegExp(
      pattern,
      caseSensitive: !seen.contains('i'),
      multiLine: seen.contains('m'),
      dotAll: seen.contains('s'),
      unicode: seen.contains('u') || seen.contains('v'),
    );
    final canonical = [
      for (final f in known.split(''))
        if (seen.contains(f)) f,
    ].join();
    return JsRegExp._(escapeRegExpSource(pattern), canonical, regExp);
  }

  /// `regexp.source`.
  final String source;

  /// `regexp.flags`, in JavaScript's order.
  final String flags;
  final RegExp regExp;

  /// `regexp.test(value)`: on `String(value)`.
  bool test(Object? value) => regExp.hasMatch(jsToString(value));

  @override
  String toString() => '/$source/$flags';
}

/// The `source` JavaScript gives a pattern: `(?:)` for an empty one,
/// slashes outside character classes and line terminators escaped.
String escapeRegExpSource(String pattern) {
  if (pattern.isEmpty) return '(?:)';
  final out = StringBuffer();
  var inClass = false;
  for (var i = 0; i < pattern.length; i++) {
    final c = pattern[i];
    if (c == r'\') {
      out.write(c);
      if (i + 1 < pattern.length) {
        i++;
        final next = pattern[i];
        out.write(switch (next) {
          '\n' => 'n',
          '\r' => 'r',
          '\u2028' => 'u2028',
          '\u2029' => 'u2029',
          _ => next,
        });
      }
      continue;
    }
    switch (c) {
      case '/' when !inClass:
        out.write(r'\/');
      case '[':
        inClass = true;
        out.write(c);
      case ']':
        inClass = false;
        out.write(c);
      case '\n':
        out.write(r'\n');
      case '\r':
        out.write(r'\r');
      case '\u2028':
        out.write(r'\u2028');
      case '\u2029':
        out.write(r'\u2029');
      default:
        out.write(c);
    }
  }
  return out.toString();
}
