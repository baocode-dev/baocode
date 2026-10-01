/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// A keybinding's `when` clause: context keys combined with `!`, `&&`,
// `||`, `==`, `!=` and parentheses (`editorTextFocus && !editorReadonly`).
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/platform/contextkey/common/contextkey.ts (`Parser`,
// `ContextKeyExpr` and its `has`/`not`/`equals`/`notEquals`/`and`/`or`
// expressions) and src/vs/platform/contextkey/common/scanner.ts.
//
// Deviations:
// - No regular expressions (`=~`), `in`/`not in` or comparisons (`<`,
//   `>=`, …): a clause using them does not parse (see [WhenExpression.error]),
//   and a keybinding with it never applies.
// - No normalization or simplification of the expressions; equality of two
//   clauses (for removals) compares their serialized forms.

import 'package:flutter/foundation.dart';

/// Reads a context key's value (null: not set).
typedef ContextLookup = Object? Function(String key);

/// A parsed `when` clause.
@immutable
sealed class WhenExpression {
  const WhenExpression();

  /// Parses [text]; a [WhenError] when it does not parse.
  static WhenExpression parse(String text) {
    final parser = _Parser(text);
    try {
      final expression = parser.parse();
      return expression;
    } on FormatException catch (error) {
      return WhenError(text, error.message);
    }
  }

  /// Whether the clause holds in [context].
  bool evaluate(ContextLookup context);

  /// The context keys it reads.
  Set<String> get keys;

  /// Why it did not parse; null when it did.
  String? get error => null;

  /// Written back as upstream serializes it.
  String serialize();

  @override
  bool operator ==(Object other) =>
      other is WhenExpression && other.serialize() == serialize();

  @override
  int get hashCode => serialize().hashCode;

  @override
  String toString() => serialize();
}

/// A clause that did not parse: it never holds.
final class WhenError extends WhenExpression {
  const WhenError(this.text, this.message);

  final String text;
  final String message;

  @override
  bool evaluate(ContextLookup context) => false;

  @override
  Set<String> get keys => const {};

  @override
  String? get error => message;

  @override
  String serialize() => text;
}

final class _Constant extends WhenExpression {
  const _Constant(this.value);

  final bool value;

  @override
  bool evaluate(ContextLookup context) => value;

  @override
  Set<String> get keys => const {};

  @override
  String serialize() => '$value';
}

/// `key`: set to a truthy value (upstream `ContextKeyDefinedExpr`).
final class _Has extends WhenExpression {
  const _Has(this.key);

  final String key;

  @override
  bool evaluate(ContextLookup context) => _truthy(context(key));

  @override
  Set<String> get keys => {key};

  @override
  String serialize() => key;
}

/// `key == value` / `key != value`.
final class _Equals extends WhenExpression {
  const _Equals(this.key, this.value, {required this.negated});

  final String key;
  final String value;
  final bool negated;

  @override
  bool evaluate(ContextLookup context) {
    final actual = context(key);
    // Upstream compares loosely (`==`): a number equals its text.
    final equal = actual != null && '$actual' == value;
    return negated ? !equal : equal;
  }

  @override
  Set<String> get keys => {key};

  @override
  String serialize() => "$key ${negated ? '!=' : '=='} '$value'";
}

final class _Not extends WhenExpression {
  const _Not(this.expression);

  final WhenExpression expression;

  @override
  bool evaluate(ContextLookup context) => !expression.evaluate(context);

  @override
  Set<String> get keys => expression.keys;

  @override
  String serialize() => switch (expression) {
    _Has() || _Constant() => '!${expression.serialize()}',
    _ => '!(${expression.serialize()})',
  };
}

final class _And extends WhenExpression {
  const _And(this.expressions);

  final List<WhenExpression> expressions;

  @override
  bool evaluate(ContextLookup context) =>
      expressions.every((expression) => expression.evaluate(context));

  @override
  Set<String> get keys => {for (final e in expressions) ...e.keys};

  @override
  String serialize() => expressions
      .map((e) => e is _Or ? '(${e.serialize()})' : e.serialize())
      .join(' && ');
}

final class _Or extends WhenExpression {
  const _Or(this.expressions);

  final List<WhenExpression> expressions;

  @override
  bool evaluate(ContextLookup context) =>
      expressions.any((expression) => expression.evaluate(context));

  @override
  Set<String> get keys => {for (final e in expressions) ...e.keys};

  @override
  String serialize() => expressions.map((e) => e.serialize()).join(' || ');
}

/// JavaScript's truthiness, as upstream tests a key.
bool _truthy(Object? value) => switch (value) {
  null || false => false,
  final String text => text.isNotEmpty,
  final num number => number != 0 && !number.isNaN,
  _ => true,
};

enum _Token { lParen, rParen, not, and, or, eq, neq, str, quoted, end }

/// Upstream's recursive descent `Parser`, over the tokens of `Scanner`.
class _Parser {
  _Parser(this.text);

  final String text;
  int _offset = 0;
  late (_Token, String) _current = _next();

  WhenExpression parse() {
    if (_current.$1 == _Token.end) return const _Constant(true);
    final expression = _or();
    if (_current.$1 != _Token.end) {
      throw FormatException('Unexpected "${_current.$2}"');
    }
    return expression;
  }

  WhenExpression _or() {
    final items = [_and()];
    while (_current.$1 == _Token.or) {
      _advance();
      items.add(_and());
    }
    return items.length == 1 ? items.single : _Or(items);
  }

  WhenExpression _and() {
    final items = [_term()];
    while (_current.$1 == _Token.and) {
      _advance();
      items.add(_term());
    }
    return items.length == 1 ? items.single : _And(items);
  }

  WhenExpression _term() {
    if (_current.$1 == _Token.not) {
      _advance();
      return _Not(_term());
    }
    return _primary();
  }

  WhenExpression _primary() {
    final (token, value) = _current;
    switch (token) {
      case _Token.lParen:
        _advance();
        final expression = _or();
        if (_current.$1 != _Token.rParen) {
          throw const FormatException('Expected ")"');
        }
        _advance();
        return expression;
      case _Token.str:
        _advance();
        if (value == 'true') return const _Constant(true);
        if (value == 'false') return const _Constant(false);
        if (_current.$1 == _Token.eq || _current.$1 == _Token.neq) {
          final negated = _current.$1 == _Token.neq;
          _advance();
          final (valueToken, operand) = _current;
          if (valueToken != _Token.str && valueToken != _Token.quoted) {
            throw const FormatException('Expected a value');
          }
          _advance();
          // Upstream: `key == true` is `key`, `key == false` is `!key`.
          if (valueToken == _Token.str &&
              (operand == 'true' || operand == 'false')) {
            final has = _Has(value);
            return (operand == 'true') != negated ? has : _Not(has);
          }
          return _Equals(value, operand, negated: negated);
        }
        return _Has(value);
      case _Token.quoted:
        throw FormatException('Unexpected "$value"');
      default:
        throw FormatException(
          token == _Token.end ? 'Unexpected end' : 'Unexpected "$value"',
        );
    }
  }

  void _advance() => _current = _next();

  static final _word = RegExp(r"[^\s()!&|=<>'~]+");

  (_Token, String) _next() {
    while (_offset < text.length && text[_offset].trim().isEmpty) {
      _offset++;
    }
    if (_offset >= text.length) return (_Token.end, '');
    final rest = text.substring(_offset);
    (_Token, String) take(_Token token, int length) {
      final value = rest.substring(0, length);
      _offset += length;
      return (token, value);
    }

    if (rest.startsWith('&&')) return take(_Token.and, 2);
    if (rest.startsWith('||')) return take(_Token.or, 2);
    if (rest.startsWith('!==')) return take(_Token.neq, 3);
    if (rest.startsWith('!=')) return take(_Token.neq, 2);
    if (rest.startsWith('===')) return take(_Token.eq, 3);
    if (rest.startsWith('==')) return take(_Token.eq, 2);
    switch (rest[0]) {
      case '(':
        return take(_Token.lParen, 1);
      case ')':
        return take(_Token.rParen, 1);
      case '!':
        return take(_Token.not, 1);
      case "'":
        final end = rest.indexOf("'", 1);
        if (end < 0) throw const FormatException('Unterminated string');
        _offset += end + 1;
        return (_Token.quoted, rest.substring(1, end));
    }
    final match = _word.matchAsPrefix(rest);
    if (match == null) {
      throw FormatException('Unsupported "${rest.split(RegExp(r'\s')).first}"');
    }
    final word = match.group(0)!;
    if (word == 'in' || word == 'not') {
      throw FormatException('Unsupported "$word"');
    }
    return take(_Token.str, word.length);
  }
}
