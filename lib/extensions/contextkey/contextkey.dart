/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Context key (`when`) expressions: the parser, the normalized expression
// tree and its evaluation, as extensions' `when`, `enablement` and
// keybinding clauses use them.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/platform/contextkey/common/contextkey.ts (`Parser`,
// `ContextKeyExpr`, every `ContextKey*Expr`, `implies`,
// `validateWhenClauses`, `expressionsAreEqualWithConstantSubstitution`,
// `CONSTANT_VALUES`/`setConstant`).
//
// Deviations:
// - A context is a lookup function ([ContextKeyLookup]) rather than an
//   `IContext` object; `null` stands for `undefined`.
// - JavaScript's value semantics come from js_values.dart (`==` is loose,
//   `=~` tests `String(value)`); regular expressions are Dart's, which
//   follow JavaScript's syntax.
// - The platform constants (`isMac`, …) come from Flutter's
//   [defaultTargetPlatform], read once, on first use; `isEdge`,
//   `isFirefox`, `isChrome` and `isSafari` are false (no browser).
// - `RawContextKey` and the service interfaces live in
//   context_key_service.dart; messages are not localized (they are for
//   extension authors).
// - Sorting is stable, as JavaScript's `Array.prototype.sort` is.

import 'package:flutter/foundation.dart';

import 'js_values.dart';
import 'scanner.dart';

/// Reads a context key's value (null: not set).
typedef ContextKeyLookup = Object? Function(String key);

// --- constants ---------------------------------------------------------------

Map<String, bool>? _constantValues;

Map<String, bool> get _constants => _constantValues ??= _platformConstants();

Map<String, bool> _platformConstants() {
  final platform = defaultTargetPlatform;
  final isMac = platform == TargetPlatform.macOS;
  return {
    'false': false,
    'true': true,
    'isMac': isMac,
    'isLinux': platform == TargetPlatform.linux,
    'isWindows': platform == TargetPlatform.windows,
    'isWeb': kIsWeb,
    'isMacNative': isMac && !kIsWeb,
    'isEdge': false,
    'isFirefox': false,
    'isChrome': false,
    'isSafari': false,
  };
}

/// The constant context keys and their values (`CONSTANT_VALUES`).
Map<String, bool> get contextKeyConstants => Map.unmodifiable(_constants);

/// `setConstant`: a constant known only after startup.
void setContextKeyConstant(String key, bool value) {
  if (_constants.containsKey(key)) {
    throw ArgumentError(
      'contextkey.setConstant(k, v) invoked with already set constant `k`',
    );
  }
  _constants[key] = value;
}

/// Reads the platform again (tests that override it).
@visibleForTesting
void debugResetContextKeyConstants() => _constantValues = null;

// --- parser ------------------------------------------------------------------

/// `ContextKeyExprType`: the order expressions sort in.
enum ContextKeyExprType {
  falseExpr,
  trueExpr,
  defined,
  not,
  equals,
  notEquals,
  and,
  regex,
  notRegex,
  or,
  inExpr,
  notIn,
  greater,
  greaterEquals,
  smaller,
  smallerEquals,
}

/// `IContextKeyExprMapper`.
abstract interface class ContextKeyExprMapper {
  ContextKeyExpression mapDefined(String key);
  ContextKeyExpression mapNot(String key);
  ContextKeyExpression mapEquals(String key, Object? value);
  ContextKeyExpression mapNotEquals(String key, Object? value);
  ContextKeyExpression mapGreater(String key, Object? value);
  ContextKeyExpression mapGreaterEquals(String key, Object? value);
  ContextKeyExpression mapSmaller(String key, Object? value);
  ContextKeyExpression mapSmallerEquals(String key, Object? value);
  ContextKeyRegexExpr mapRegex(String key, JsRegExp? regexp);
  ContextKeyInExpr mapIn(String key, String valueKey);
  ContextKeyNotInExpr mapNotIn(String key, String valueKey);
}

/// `ParsingError`.
final class ParsingError {
  const ParsingError({
    required this.message,
    required this.offset,
    required this.lexeme,
    this.additionalInfo,
  });

  final String message;
  final int offset;
  final String lexeme;
  final String? additionalInfo;
}

const _errorEmptyString = 'Empty context key expression';
const _hintEmptyString =
    "Did you forget to write an expression? You can also put 'false' or "
    "'true' to always evaluate to false or true, respectively.";
const _errorNoInAfterNot = "'in' after 'not'.";
const _errorClosingParenthesis = "closing parenthesis ')'";
const _errorUnexpectedToken = 'Unexpected token';
const _hintUnexpectedToken = 'Did you forget to put && or || before the token?';
const _errorUnexpectedEOF = 'Unexpected end of expression';
const _hintUnexpectedEOF = 'Did you forget to put a context key?';

final class _ParseError implements Exception {
  const _ParseError();
}

/// `Parser`: parses a `when` clause into a normalized expression.
final class Parser {
  Parser({this.regexParsingWithErrorRecovery = true});

  /// Recovers from regular expressions with unescaped slashes (`/src//` as
  /// `/src\//`), as extensions write them.
  final bool regexParsingWithErrorRecovery;

  final _scanner = Scanner();
  List<Token> _tokens = [];
  int _current = 0;
  List<ParsingError> _parsingErrors = [];

  List<LexingError> get lexingErrors => _scanner.errors;
  List<ParsingError> get parsingErrors => List.unmodifiable(_parsingErrors);

  /// The expression; null when [input] has errors ([lexingErrors],
  /// [parsingErrors]).
  ContextKeyExpression? parse(String input) {
    if (input.isEmpty) {
      _parsingErrors.add(
        const ParsingError(
          message: _errorEmptyString,
          offset: 0,
          lexeme: '',
          additionalInfo: _hintEmptyString,
        ),
      );
      return null;
    }
    _tokens = _scanner.reset(input).scan();
    _current = 0;
    _parsingErrors = [];
    try {
      final expr = _expr();
      if (!_isAtEnd) {
        final peek = _peek;
        final additionalInfo = peek.type == TokenType.str
            ? _hintUnexpectedToken
            : null;
        _parsingErrors.add(
          ParsingError(
            message: _errorUnexpectedToken,
            offset: peek.offset,
            lexeme: Scanner.getLexeme(peek),
            additionalInfo: additionalInfo,
          ),
        );
        throw const _ParseError();
      }
      return expr;
    } on _ParseError {
      return null;
    }
  }

  ContextKeyExpression? _expr() => _or();

  ContextKeyExpression? _or() {
    final expr = [_and()];
    while (_matchOne(TokenType.or)) {
      expr.add(_and());
    }
    return expr.length == 1 ? expr[0] : ContextKeyExpr.or(expr);
  }

  ContextKeyExpression? _and() {
    final expr = [_term()];
    while (_matchOne(TokenType.and)) {
      expr.add(_term());
    }
    return expr.length == 1 ? expr[0] : ContextKeyExpr.and(expr);
  }

  ContextKeyExpression? _term() {
    if (_matchOne(TokenType.neg)) {
      final peek = _peek;
      switch (peek.type) {
        case TokenType.trueKeyword:
          _advance();
          return ContextKeyFalseExpr.instance;
        case TokenType.falseKeyword:
          _advance();
          return ContextKeyTrueExpr.instance;
        case TokenType.lParen:
          _advance();
          final expr = _expr();
          _consume(TokenType.rParen, _errorClosingParenthesis);
          return expr?.negate();
        case TokenType.str:
          _advance();
          return ContextKeyNotExpr.create(peek.lexeme!);
        default:
          throw _errExpectedButGot(
            "KEY | true | false | '(' expression ')'",
            peek,
          );
      }
    }
    return _primary();
  }

  ContextKeyExpression? _primary() {
    final peek = _peek;
    switch (peek.type) {
      case TokenType.trueKeyword:
        _advance();
        return ContextKeyExpr.trueExpr();
      case TokenType.falseKeyword:
        _advance();
        return ContextKeyExpr.falseExpr();
      case TokenType.lParen:
        _advance();
        final expr = _expr();
        _consume(TokenType.rParen, _errorClosingParenthesis);
        return expr;
      case TokenType.str:
        final key = peek.lexeme!;
        _advance();
        if (_matchOne(TokenType.regexOp)) return _regex(key);
        if (_matchOne(TokenType.notKeyword)) {
          _consume(TokenType.inKeyword, _errorNoInAfterNot);
          return ContextKeyExpr.notIn(key, _value());
        }
        switch (_peek.type) {
          case TokenType.eq:
            _advance();
            final right = _value();
            if (_previous.type == TokenType.quotedStr) {
              return ContextKeyExpr.equals(key, right);
            }
            return switch (right) {
              'true' => ContextKeyExpr.has(key),
              'false' => ContextKeyExpr.not(key),
              _ => ContextKeyExpr.equals(key, right),
            };
          case TokenType.notEq:
            _advance();
            final right = _value();
            if (_previous.type == TokenType.quotedStr) {
              return ContextKeyExpr.notEquals(key, right);
            }
            return switch (right) {
              'true' => ContextKeyExpr.not(key),
              'false' => ContextKeyExpr.has(key),
              _ => ContextKeyExpr.notEquals(key, right),
            };
          case TokenType.lt:
            _advance();
            return ContextKeySmallerExpr.create(key, _value());
          case TokenType.ltEq:
            _advance();
            return ContextKeySmallerEqualsExpr.create(key, _value());
          case TokenType.gt:
            _advance();
            return ContextKeyGreaterExpr.create(key, _value());
          case TokenType.gtEq:
            _advance();
            return ContextKeyGreaterEqualsExpr.create(key, _value());
          case TokenType.inKeyword:
            _advance();
            return ContextKeyExpr.inExpr(key, _value());
          default:
            return ContextKeyExpr.has(key);
        }
      case TokenType.eof:
        _parsingErrors.add(
          ParsingError(
            message: _errorUnexpectedEOF,
            offset: peek.offset,
            lexeme: '',
            additionalInfo: _hintUnexpectedEOF,
          ),
        );
        throw const _ParseError();
      default:
        throw _errExpectedButGot(
          "true | false | KEY \n\t| KEY '=~' REGEX \n\t| KEY ('==' | '!=' | "
          "'<' | '<=' | '>' | '>=' | 'in' | 'not' 'in') value",
          _peek,
        );
    }
  }

  ContextKeyExpression _regex(String key) {
    final expr = _peek;
    if (!regexParsingWithErrorRecovery) {
      _advance();
      if (expr.type != TokenType.regexStr) {
        throw _errExpectedButGot('REGEX', expr);
      }
      final regexLexeme = expr.lexeme!;
      final closingSlashIndex = regexLexeme.lastIndexOf('/');
      final flags = closingSlashIndex == regexLexeme.length - 1
          ? ''
          : _removeFlagsGY(regexLexeme.substring(closingSlashIndex + 1));
      final JsRegExp regexp;
      try {
        regexp = JsRegExp(regexLexeme.substring(1, closingSlashIndex), flags);
      } on FormatException {
        throw _errExpectedButGot('REGEX', expr);
      }
      return ContextKeyRegexExpr.create(key, regexp);
    }
    switch (expr.type) {
      case TokenType.regexStr || TokenType.error:
        final lexemeReconstruction = [expr.lexeme!];
        _advance();
        var followingToken = _peek;
        var parenBalance = 0;
        for (final c in expr.lexeme!.codeUnits) {
          if (c == 0x28) {
            parenBalance++;
          } else if (c == 0x29) {
            parenBalance--;
          }
        }
        while (!_isAtEnd &&
            followingToken.type != TokenType.and &&
            followingToken.type != TokenType.or) {
          switch (followingToken.type) {
            case TokenType.lParen:
              parenBalance++;
            case TokenType.rParen:
              parenBalance--;
            case TokenType.regexStr || TokenType.quotedStr:
              final lexeme = followingToken.lexeme!;
              for (var i = 0; i < lexeme.length; i++) {
                if (lexeme.codeUnitAt(i) == 0x28) {
                  parenBalance++;
                } else if (i < expr.lexeme!.length &&
                    expr.lexeme!.codeUnitAt(i) == 0x29) {
                  // As upstream: it reads the first token's lexeme here.
                  parenBalance--;
                }
              }
            default:
              break;
          }
          if (parenBalance < 0) break;
          lexemeReconstruction.add(Scanner.getLexeme(followingToken));
          _advance();
          followingToken = _peek;
        }
        final regexLexeme = lexemeReconstruction.join();
        final closingSlashIndex = regexLexeme.lastIndexOf('/');
        final flags = closingSlashIndex == regexLexeme.length - 1
            ? ''
            : _removeFlagsGY(regexLexeme.substring(closingSlashIndex + 1));
        final JsRegExp regexp;
        try {
          if (closingSlashIndex < 1) throw const FormatException();
          regexp = JsRegExp(regexLexeme.substring(1, closingSlashIndex), flags);
        } on FormatException {
          throw _errExpectedButGot('REGEX', expr);
        }
        return ContextKeyExpr.regex(key, regexp);
      case TokenType.quotedStr:
        final serializedValue = expr.lexeme!;
        _advance();
        JsRegExp? regex;
        if (serializedValue.trim().isNotEmpty) {
          final start = serializedValue.indexOf('/');
          final end = serializedValue.lastIndexOf('/');
          if (start != end && start >= 0) {
            final value = serializedValue.substring(start + 1, end);
            final caseIgnoreFlag =
                end + 1 < serializedValue.length &&
                    serializedValue[end + 1] == 'i'
                ? 'i'
                : '';
            try {
              regex = JsRegExp(value, caseIgnoreFlag);
            } on FormatException {
              throw _errExpectedButGot('REGEX', expr);
            }
          }
        }
        if (regex == null) throw _errExpectedButGot('REGEX', expr);
        return ContextKeyRegexExpr.create(key, regex);
      default:
        throw _errExpectedButGot('REGEX', _peek);
    }
  }

  String _value() {
    final token = _peek;
    switch (token.type) {
      case TokenType.str || TokenType.quotedStr:
        _advance();
        return token.lexeme!;
      case TokenType.trueKeyword:
        _advance();
        return 'true';
      case TokenType.falseKeyword:
        _advance();
        return 'false';
      case TokenType.inKeyword:
        _advance();
        return 'in';
      default:
        // `"when": "foo == "`, which existing extensions use.
        return '';
    }
  }

  static String _removeFlagsGY(String flags) =>
      flags.replaceAll(RegExp('[gy]'), '');

  Token get _previous => _tokens[_current - 1];

  bool _matchOne(TokenType type) {
    if (_check(type)) {
      _advance();
      return true;
    }
    return false;
  }

  Token _advance() {
    if (!_isAtEnd) _current++;
    return _previous;
  }

  Token _consume(TokenType type, String message) {
    if (_check(type)) return _advance();
    throw _errExpectedButGot(message, _peek);
  }

  _ParseError _errExpectedButGot(
    String expected,
    Token got, [
    String? additionalInfo,
  ]) {
    final lexeme = Scanner.getLexeme(got);
    _parsingErrors.add(
      ParsingError(
        message: "Expected: $expected\nReceived: '$lexeme'.",
        offset: got.offset,
        lexeme: lexeme,
        additionalInfo: additionalInfo,
      ),
    );
    return const _ParseError();
  }

  bool _check(TokenType type) => _peek.type == type;

  Token get _peek => _tokens[_current];

  bool get _isAtEnd => _peek.type == TokenType.eof;
}

/// `ContextKeyExpr`: makes normalized expressions.
abstract final class ContextKeyExpr {
  static ContextKeyExpression falseExpr() => ContextKeyFalseExpr.instance;
  static ContextKeyExpression trueExpr() => ContextKeyTrueExpr.instance;
  static ContextKeyExpression has(String key) =>
      ContextKeyDefinedExpr.create(key);
  static ContextKeyExpression equals(String key, Object? value) =>
      ContextKeyEqualsExpr.create(key, value);
  static ContextKeyExpression notEquals(String key, Object? value) =>
      ContextKeyNotEqualsExpr.create(key, value);
  static ContextKeyExpression regex(String key, JsRegExp value) =>
      ContextKeyRegexExpr.create(key, value);
  static ContextKeyExpression inExpr(String key, String value) =>
      ContextKeyInExpr.create(key, value);
  static ContextKeyExpression notIn(String key, String value) =>
      ContextKeyNotInExpr.create(key, value);
  static ContextKeyExpression not(String key) => ContextKeyNotExpr.create(key);
  static ContextKeyExpression? and(List<ContextKeyExpression?> expr) =>
      ContextKeyAndExpr.create(expr, null, true);
  static ContextKeyExpression? or(List<ContextKeyExpression?> expr) =>
      ContextKeyOrExpr.create(expr, null, true);
  static ContextKeyExpression greater(String key, num value) =>
      ContextKeyGreaterExpr.create(key, value);
  static ContextKeyExpression greaterEquals(String key, num value) =>
      ContextKeyGreaterEqualsExpr.create(key, value);
  static ContextKeyExpression smaller(String key, num value) =>
      ContextKeySmallerExpr.create(key, value);
  static ContextKeyExpression smallerEquals(String key, num value) =>
      ContextKeySmallerEqualsExpr.create(key, value);

  static final _parser = Parser(regexParsingWithErrorRecovery: false);

  /// Parses [serialized] strictly (no regex recovery); null when it is null
  /// or does not parse.
  static ContextKeyExpression? deserialize(String? serialized) {
    if (serialized == null) return null;
    return _parser.parse(serialized);
  }

  /// Parses [serialized] with regex recovery (`/src//` as `/src\//`), as
  /// [Parser]'s default; null when it is null or does not parse.
  static ContextKeyExpression? deserializeLenient(String? serialized) {
    if (serialized == null) return null;
    return Parser().parse(serialized);
  }
}

/// One error of a `when` clause, for diagnostics (`validateWhenClauses`).
typedef WhenClauseError = ({String errorMessage, int offset, int length});

/// `validateWhenClauses`.
List<List<WhenClauseError>> validateWhenClauses(List<String> whenClauses) {
  final parser = Parser(regexParsingWithErrorRecovery: false);
  return [
    for (final whenClause in whenClauses)
      () {
        parser.parse(whenClause);
        if (parser.lexingErrors.isNotEmpty) {
          return [
            for (final se in parser.lexingErrors)
              (
                errorMessage: se.additionalInfo != null
                    ? 'Unexpected token. Hint: ${se.additionalInfo}'
                    : 'Unexpected token.',
                offset: se.offset,
                length: se.lexeme.length,
              ),
          ];
        }
        if (parser.parsingErrors.isNotEmpty) {
          return [
            for (final pe in parser.parsingErrors)
              (
                errorMessage: pe.additionalInfo != null
                    ? '${pe.message}. ${pe.additionalInfo}'
                    : pe.message,
                offset: pe.offset,
                length: pe.lexeme.length,
              ),
          ];
        }
        return <WhenClauseError>[];
      }(),
  ];
}

/// `expressionsAreEqualWithConstantSubstitution`.
bool expressionsAreEqualWithConstantSubstitution(
  ContextKeyExpression? a,
  ContextKeyExpression? b,
) {
  final aExpr = a?.substituteConstants();
  final bExpr = b?.substituteConstants();
  if (aExpr == null && bExpr == null) return true;
  if (aExpr == null || bExpr == null) return false;
  return aExpr.equals(bExpr);
}

// --- expressions -------------------------------------------------------------

/// `ContextKeyExpression`.
sealed class ContextKeyExpression {
  ContextKeyExpression();

  ContextKeyExprType get type;

  int cmp(ContextKeyExpression other);
  bool equals(ContextKeyExpression other);
  ContextKeyExpression? substituteConstants();
  bool evaluate(ContextKeyLookup context);
  String serialize();
  List<String> keys();
  ContextKeyExpression map(ContextKeyExprMapper mapFnc);
  ContextKeyExpression negate();

  @override
  bool operator ==(Object other) =>
      other is ContextKeyExpression && equals(other);

  @override
  int get hashCode => Object.hash(type, Object.hashAll(keys()));

  @override
  String toString() => serialize();
}

int _cmp1(String key1, String key2) => key1.compareTo(key2).sign;

int _cmp2(String key1, Object? value1, String key2, Object? value2) {
  final k = key1.compareTo(key2);
  if (k != 0) return k.sign;
  if (jsLessThan(value1, value2)) return -1;
  if (jsLessThan(value2, value1)) return 1;
  return 0;
}

final class ContextKeyFalseExpr extends ContextKeyExpression {
  ContextKeyFalseExpr._();
  static final instance = ContextKeyFalseExpr._();

  @override
  ContextKeyExprType get type => ContextKeyExprType.falseExpr;
  @override
  int cmp(ContextKeyExpression other) => type.index - other.type.index;
  @override
  bool equals(ContextKeyExpression other) => other.type == type;
  @override
  ContextKeyExpression substituteConstants() => this;
  @override
  bool evaluate(ContextKeyLookup context) => false;
  @override
  String serialize() => 'false';
  @override
  List<String> keys() => const [];
  @override
  ContextKeyExpression map(ContextKeyExprMapper mapFnc) => this;
  @override
  ContextKeyExpression negate() => ContextKeyTrueExpr.instance;
}

final class ContextKeyTrueExpr extends ContextKeyExpression {
  ContextKeyTrueExpr._();
  static final instance = ContextKeyTrueExpr._();

  @override
  ContextKeyExprType get type => ContextKeyExprType.trueExpr;
  @override
  int cmp(ContextKeyExpression other) => type.index - other.type.index;
  @override
  bool equals(ContextKeyExpression other) => other.type == type;
  @override
  ContextKeyExpression substituteConstants() => this;
  @override
  bool evaluate(ContextKeyLookup context) => true;
  @override
  String serialize() => 'true';
  @override
  List<String> keys() => const [];
  @override
  ContextKeyExpression map(ContextKeyExprMapper mapFnc) => this;
  @override
  ContextKeyExpression negate() => ContextKeyFalseExpr.instance;
}

/// `key`: holds when the key's value is truthy.
final class ContextKeyDefinedExpr extends ContextKeyExpression {
  ContextKeyDefinedExpr(this.key, [this._negated]);

  static ContextKeyExpression create(
    String key, [
    ContextKeyExpression? negated,
  ]) {
    final constantValue = _constants[key];
    if (constantValue != null) {
      return constantValue
          ? ContextKeyTrueExpr.instance
          : ContextKeyFalseExpr.instance;
    }
    return ContextKeyDefinedExpr(key, negated);
  }

  final String key;
  ContextKeyExpression? _negated;

  @override
  ContextKeyExprType get type => ContextKeyExprType.defined;
  @override
  int cmp(ContextKeyExpression other) {
    if (other.type != type) return type.index - other.type.index;
    return _cmp1(key, (other as ContextKeyDefinedExpr).key);
  }

  @override
  bool equals(ContextKeyExpression other) =>
      other is ContextKeyDefinedExpr && other.type == type && key == other.key;
  @override
  ContextKeyExpression substituteConstants() {
    final constantValue = _constants[key];
    if (constantValue != null) {
      return constantValue
          ? ContextKeyTrueExpr.instance
          : ContextKeyFalseExpr.instance;
    }
    return this;
  }

  @override
  bool evaluate(ContextKeyLookup context) => jsTruthy(context(key));
  @override
  String serialize() => key;
  @override
  List<String> keys() => [key];
  @override
  ContextKeyExpression map(ContextKeyExprMapper mapFnc) =>
      mapFnc.mapDefined(key);
  @override
  ContextKeyExpression negate() =>
      _negated ??= ContextKeyNotExpr.create(key, this);
}

final class ContextKeyEqualsExpr extends ContextKeyExpression {
  ContextKeyEqualsExpr._(this.key, this.value, this._negated);

  static ContextKeyExpression create(
    String key,
    Object? value, [
    ContextKeyExpression? negated,
  ]) {
    if (value is bool) {
      return value
          ? ContextKeyDefinedExpr.create(key, negated)
          : ContextKeyNotExpr.create(key, negated);
    }
    final constantValue = _constants[key];
    if (constantValue != null) {
      final trueValue = constantValue ? 'true' : 'false';
      return value == trueValue
          ? ContextKeyTrueExpr.instance
          : ContextKeyFalseExpr.instance;
    }
    return ContextKeyEqualsExpr._(key, value, negated);
  }

  final String key;
  final Object? value;
  ContextKeyExpression? _negated;

  @override
  ContextKeyExprType get type => ContextKeyExprType.equals;
  @override
  int cmp(ContextKeyExpression other) {
    if (other.type != type) return type.index - other.type.index;
    final o = other as ContextKeyEqualsExpr;
    return _cmp2(key, value, o.key, o.value);
  }

  @override
  bool equals(ContextKeyExpression other) =>
      other is ContextKeyEqualsExpr &&
      key == other.key &&
      jsStrictEquals(value, other.value);
  @override
  ContextKeyExpression substituteConstants() {
    final constantValue = _constants[key];
    if (constantValue != null) {
      final trueValue = constantValue ? 'true' : 'false';
      return value == trueValue
          ? ContextKeyTrueExpr.instance
          : ContextKeyFalseExpr.instance;
    }
    return this;
  }

  @override
  bool evaluate(ContextKeyLookup context) => jsLooseEquals(context(key), value);
  @override
  String serialize() => "$key == '${jsToString(value)}'";
  @override
  List<String> keys() => [key];
  @override
  ContextKeyExpression map(ContextKeyExprMapper mapFnc) =>
      mapFnc.mapEquals(key, value);
  @override
  ContextKeyExpression negate() =>
      _negated ??= ContextKeyNotEqualsExpr.create(key, value, this);
}

final class ContextKeyInExpr extends ContextKeyExpression {
  ContextKeyInExpr._(this.key, this.valueKey);

  static ContextKeyInExpr create(String key, String valueKey) =>
      ContextKeyInExpr._(key, valueKey);

  final String key;
  final String valueKey;
  ContextKeyExpression? _negated;

  /// Whether file URIs compare without case (Windows' file system).
  static bool get _isWindows => _constants['isWindows'] ?? false;

  @override
  ContextKeyExprType get type => ContextKeyExprType.inExpr;
  @override
  int cmp(ContextKeyExpression other) {
    if (other.type != type) return type.index - other.type.index;
    final o = other as ContextKeyInExpr;
    return _cmp2(key, valueKey, o.key, o.valueKey);
  }

  @override
  bool equals(ContextKeyExpression other) =>
      other is ContextKeyInExpr &&
      key == other.key &&
      valueKey == other.valueKey;
  @override
  ContextKeyExpression substituteConstants() => this;

  @override
  bool evaluate(ContextKeyLookup context) {
    final source = context(valueKey);
    final item = context(key);
    if (source is List) {
      if (source.contains(item)) return true;
      if (_isWindows && item is String && item.startsWith('file:///')) {
        final itemLower = item.toLowerCase();
        return source.any((s) => s is String && s.toLowerCase() == itemLower);
      }
      return false;
    }
    if (item is String && source is Map) {
      if (source.containsKey(item)) return true;
      if (_isWindows && item.startsWith('file:///')) {
        final itemLower = item.toLowerCase();
        return source.keys.any(
          (k) => k is String && k.toLowerCase() == itemLower,
        );
      }
      return false;
    }
    return false;
  }

  @override
  String serialize() => "$key in '$valueKey'";
  @override
  List<String> keys() => [key, valueKey];
  @override
  ContextKeyInExpr map(ContextKeyExprMapper mapFnc) =>
      mapFnc.mapIn(key, valueKey);
  @override
  ContextKeyExpression negate() =>
      _negated ??= ContextKeyNotInExpr.create(key, valueKey);
}

final class ContextKeyNotInExpr extends ContextKeyExpression {
  ContextKeyNotInExpr._(this.key, this.valueKey)
    : _negated = ContextKeyInExpr.create(key, valueKey);

  static ContextKeyNotInExpr create(String key, String valueKey) =>
      ContextKeyNotInExpr._(key, valueKey);

  final String key;
  final String valueKey;
  final ContextKeyInExpr _negated;

  @override
  ContextKeyExprType get type => ContextKeyExprType.notIn;
  @override
  int cmp(ContextKeyExpression other) {
    if (other.type != type) return type.index - other.type.index;
    return _negated.cmp((other as ContextKeyNotInExpr)._negated);
  }

  @override
  bool equals(ContextKeyExpression other) =>
      other is ContextKeyNotInExpr && _negated.equals(other._negated);
  @override
  ContextKeyExpression substituteConstants() => this;
  @override
  bool evaluate(ContextKeyLookup context) => !_negated.evaluate(context);
  @override
  String serialize() => "$key not in '$valueKey'";
  @override
  List<String> keys() => _negated.keys();
  @override
  ContextKeyExpression map(ContextKeyExprMapper mapFnc) =>
      mapFnc.mapNotIn(key, valueKey);
  @override
  ContextKeyExpression negate() => _negated;
}

final class ContextKeyNotEqualsExpr extends ContextKeyExpression {
  ContextKeyNotEqualsExpr._(this.key, this.value, this._negated);

  static ContextKeyExpression create(
    String key,
    Object? value, [
    ContextKeyExpression? negated,
  ]) {
    if (value is bool) {
      return value
          ? ContextKeyNotExpr.create(key, negated)
          : ContextKeyDefinedExpr.create(key, negated);
    }
    final constantValue = _constants[key];
    if (constantValue != null) {
      final falseValue = constantValue ? 'true' : 'false';
      return value == falseValue
          ? ContextKeyFalseExpr.instance
          : ContextKeyTrueExpr.instance;
    }
    return ContextKeyNotEqualsExpr._(key, value, negated);
  }

  final String key;
  final Object? value;
  ContextKeyExpression? _negated;

  @override
  ContextKeyExprType get type => ContextKeyExprType.notEquals;
  @override
  int cmp(ContextKeyExpression other) {
    if (other.type != type) return type.index - other.type.index;
    final o = other as ContextKeyNotEqualsExpr;
    return _cmp2(key, value, o.key, o.value);
  }

  @override
  bool equals(ContextKeyExpression other) =>
      other is ContextKeyNotEqualsExpr &&
      key == other.key &&
      jsStrictEquals(value, other.value);
  @override
  ContextKeyExpression substituteConstants() {
    final constantValue = _constants[key];
    if (constantValue != null) {
      final falseValue = constantValue ? 'true' : 'false';
      return value == falseValue
          ? ContextKeyFalseExpr.instance
          : ContextKeyTrueExpr.instance;
    }
    return this;
  }

  @override
  bool evaluate(ContextKeyLookup context) =>
      !jsLooseEquals(context(key), value);
  @override
  String serialize() => "$key != '${jsToString(value)}'";
  @override
  List<String> keys() => [key];
  @override
  ContextKeyExpression map(ContextKeyExprMapper mapFnc) =>
      mapFnc.mapNotEquals(key, value);
  @override
  ContextKeyExpression negate() =>
      _negated ??= ContextKeyEqualsExpr.create(key, value, this);
}

final class ContextKeyNotExpr extends ContextKeyExpression {
  ContextKeyNotExpr._(this.key, this._negated);

  static ContextKeyExpression create(
    String key, [
    ContextKeyExpression? negated,
  ]) {
    final constantValue = _constants[key];
    if (constantValue != null) {
      return constantValue
          ? ContextKeyFalseExpr.instance
          : ContextKeyTrueExpr.instance;
    }
    return ContextKeyNotExpr._(key, negated);
  }

  final String key;
  ContextKeyExpression? _negated;

  @override
  ContextKeyExprType get type => ContextKeyExprType.not;
  @override
  int cmp(ContextKeyExpression other) {
    if (other.type != type) return type.index - other.type.index;
    return _cmp1(key, (other as ContextKeyNotExpr).key);
  }

  @override
  bool equals(ContextKeyExpression other) =>
      other is ContextKeyNotExpr && key == other.key;
  @override
  ContextKeyExpression substituteConstants() {
    final constantValue = _constants[key];
    if (constantValue != null) {
      return constantValue
          ? ContextKeyFalseExpr.instance
          : ContextKeyTrueExpr.instance;
    }
    return this;
  }

  @override
  bool evaluate(ContextKeyLookup context) => !jsTruthy(context(key));
  @override
  String serialize() => '!$key';
  @override
  List<String> keys() => [key];
  @override
  ContextKeyExpression map(ContextKeyExprMapper mapFnc) => mapFnc.mapNot(key);
  @override
  ContextKeyExpression negate() =>
      _negated ??= ContextKeyDefinedExpr.create(key, this);
}

/// `withFloatOrStr`: a number when [value] reads as one.
ContextKeyExpression _withFloatOrStr(
  Object? value,
  ContextKeyExpression Function(Object value) callback,
) {
  var v = value;
  if (v is String) {
    final n = jsParseFloat(v);
    if (!n.isNaN) v = n;
  }
  if (v is String || v is num) return callback(v!);
  return ContextKeyFalseExpr.instance;
}

/// `>`, `>=`, `<` and `<=`: shared parts.
sealed class _ComparisonExpr extends ContextKeyExpression {
  _ComparisonExpr(this.key, this.value, this._negated);

  final String key;

  /// A number, or a string (never holds).
  final Object value;
  ContextKeyExpression? _negated;

  String get _op;
  bool _compare(double actual, num value);

  @override
  int cmp(ContextKeyExpression other) {
    if (other.type != type) return type.index - other.type.index;
    final o = other as _ComparisonExpr;
    return _cmp2(key, value, o.key, o.value);
  }

  @override
  bool equals(ContextKeyExpression other) =>
      other is _ComparisonExpr &&
      other.type == type &&
      key == other.key &&
      jsStrictEquals(value, other.value);
  @override
  ContextKeyExpression substituteConstants() => this;
  @override
  bool evaluate(ContextKeyLookup context) {
    final v = value;
    if (v is! num) return false;
    return _compare(jsParseFloat(context(key)), v);
  }

  @override
  String serialize() => '$key $_op ${jsToString(value)}';
  @override
  List<String> keys() => [key];
}

final class ContextKeyGreaterExpr extends _ComparisonExpr {
  ContextKeyGreaterExpr._(super.key, super.value, super.negated);

  static ContextKeyExpression create(
    String key,
    Object? value, [
    ContextKeyExpression? negated,
  ]) => _withFloatOrStr(value, (v) => ContextKeyGreaterExpr._(key, v, negated));

  @override
  ContextKeyExprType get type => ContextKeyExprType.greater;
  @override
  String get _op => '>';
  @override
  bool _compare(double actual, num value) => actual > value;
  @override
  ContextKeyExpression map(ContextKeyExprMapper mapFnc) =>
      mapFnc.mapGreater(key, value);
  @override
  ContextKeyExpression negate() =>
      _negated ??= ContextKeySmallerEqualsExpr.create(key, value, this);
}

final class ContextKeyGreaterEqualsExpr extends _ComparisonExpr {
  ContextKeyGreaterEqualsExpr._(super.key, super.value, super.negated);

  static ContextKeyExpression create(
    String key,
    Object? value, [
    ContextKeyExpression? negated,
  ]) => _withFloatOrStr(
    value,
    (v) => ContextKeyGreaterEqualsExpr._(key, v, negated),
  );

  @override
  ContextKeyExprType get type => ContextKeyExprType.greaterEquals;
  @override
  String get _op => '>=';
  @override
  bool _compare(double actual, num value) => actual >= value;
  @override
  ContextKeyExpression map(ContextKeyExprMapper mapFnc) =>
      mapFnc.mapGreaterEquals(key, value);
  @override
  ContextKeyExpression negate() =>
      _negated ??= ContextKeySmallerExpr.create(key, value, this);
}

final class ContextKeySmallerExpr extends _ComparisonExpr {
  ContextKeySmallerExpr._(super.key, super.value, super.negated);

  static ContextKeyExpression create(
    String key,
    Object? value, [
    ContextKeyExpression? negated,
  ]) => _withFloatOrStr(value, (v) => ContextKeySmallerExpr._(key, v, negated));

  @override
  ContextKeyExprType get type => ContextKeyExprType.smaller;
  @override
  String get _op => '<';
  @override
  bool _compare(double actual, num value) => actual < value;
  @override
  ContextKeyExpression map(ContextKeyExprMapper mapFnc) =>
      mapFnc.mapSmaller(key, value);
  @override
  ContextKeyExpression negate() =>
      _negated ??= ContextKeyGreaterEqualsExpr.create(key, value, this);
}

final class ContextKeySmallerEqualsExpr extends _ComparisonExpr {
  ContextKeySmallerEqualsExpr._(super.key, super.value, super.negated);

  static ContextKeyExpression create(
    String key,
    Object? value, [
    ContextKeyExpression? negated,
  ]) => _withFloatOrStr(
    value,
    (v) => ContextKeySmallerEqualsExpr._(key, v, negated),
  );

  @override
  ContextKeyExprType get type => ContextKeyExprType.smallerEquals;
  @override
  String get _op => '<=';
  @override
  bool _compare(double actual, num value) => actual <= value;
  @override
  ContextKeyExpression map(ContextKeyExprMapper mapFnc) =>
      mapFnc.mapSmallerEquals(key, value);
  @override
  ContextKeyExpression negate() =>
      _negated ??= ContextKeyGreaterExpr.create(key, value, this);
}

final class ContextKeyRegexExpr extends ContextKeyExpression {
  ContextKeyRegexExpr._(this.key, this.regexp);

  static ContextKeyRegexExpr create(String key, JsRegExp? regexp) =>
      ContextKeyRegexExpr._(key, regexp);

  final String key;
  final JsRegExp? regexp;
  ContextKeyExpression? _negated;

  @override
  ContextKeyExprType get type => ContextKeyExprType.regex;
  @override
  int cmp(ContextKeyExpression other) {
    if (other.type != type) return type.index - other.type.index;
    final o = other as ContextKeyRegexExpr;
    final k = key.compareTo(o.key);
    if (k != 0) return k.sign;
    final thisSource = regexp?.source ?? '';
    final otherSource = o.regexp?.source ?? '';
    return thisSource.compareTo(otherSource).sign;
  }

  @override
  bool equals(ContextKeyExpression other) =>
      other is ContextKeyRegexExpr &&
      key == other.key &&
      (regexp?.source ?? '') == (other.regexp?.source ?? '');
  @override
  ContextKeyExpression substituteConstants() => this;
  @override
  bool evaluate(ContextKeyLookup context) =>
      regexp?.test(context(key)) ?? false;
  @override
  String serialize() {
    final r = regexp;
    return '$key =~ ${r != null ? '/${r.source}/${r.flags}' : '/invalid/'}';
  }

  @override
  List<String> keys() => [key];
  @override
  ContextKeyRegexExpr map(ContextKeyExprMapper mapFnc) =>
      mapFnc.mapRegex(key, regexp);
  @override
  ContextKeyExpression negate() =>
      _negated ??= ContextKeyNotRegexExpr.create(this);
}

final class ContextKeyNotRegexExpr extends ContextKeyExpression {
  ContextKeyNotRegexExpr._(this._actual);

  static ContextKeyExpression create(ContextKeyRegexExpr actual) =>
      ContextKeyNotRegexExpr._(actual);

  final ContextKeyRegexExpr _actual;

  @override
  ContextKeyExprType get type => ContextKeyExprType.notRegex;
  @override
  int cmp(ContextKeyExpression other) {
    if (other.type != type) return type.index - other.type.index;
    return _actual.cmp((other as ContextKeyNotRegexExpr)._actual);
  }

  @override
  bool equals(ContextKeyExpression other) =>
      other is ContextKeyNotRegexExpr && _actual.equals(other._actual);
  @override
  ContextKeyExpression substituteConstants() => this;
  @override
  bool evaluate(ContextKeyLookup context) => !_actual.evaluate(context);
  @override
  String serialize() => '!(${_actual.serialize()})';
  @override
  List<String> keys() => _actual.keys();
  @override
  ContextKeyExpression map(ContextKeyExprMapper mapFnc) =>
      ContextKeyNotRegexExpr._(_actual.map(mapFnc));
  @override
  ContextKeyExpression negate() => _actual;
}

/// `eliminateConstantsInArray`: [arr] itself when nothing changed.
List<ContextKeyExpression?> _eliminateConstantsInArray(
  List<ContextKeyExpression> arr,
) {
  List<ContextKeyExpression?>? newArr;
  for (var i = 0; i < arr.length; i++) {
    final newExpr = arr[i].substituteConstants();
    if (!identical(arr[i], newExpr) && newArr == null) {
      newArr = [for (var j = 0; j < i; j++) arr[j]];
    }
    newArr?.add(newExpr);
  }
  return newArr ?? arr;
}

/// A stable sort by `cmp`, as JavaScript's.
void _sort(List<ContextKeyExpression> list) {
  if (list.length < 2) return;
  final sorted = _mergeSort(list);
  for (var i = 0; i < list.length; i++) {
    list[i] = sorted[i];
  }
}

List<ContextKeyExpression> _mergeSort(List<ContextKeyExpression> list) {
  if (list.length < 2) return list;
  final mid = list.length ~/ 2;
  final left = _mergeSort(list.sublist(0, mid));
  final right = _mergeSort(list.sublist(mid));
  final out = <ContextKeyExpression>[];
  var i = 0, j = 0;
  while (i < left.length && j < right.length) {
    if (right[j].cmp(left[i]) < 0) {
      out.add(right[j++]);
    } else {
      out.add(left[i++]);
    }
  }
  out
    ..addAll(left.skip(i))
    ..addAll(right.skip(j));
  return out;
}

final class ContextKeyAndExpr extends ContextKeyExpression {
  ContextKeyAndExpr._(this.expr, this._negated);

  static ContextKeyExpression? create(
    List<ContextKeyExpression?> expr,
    ContextKeyExpression? negated,
    bool extraRedundantCheck,
  ) => _normalizeArr(expr, negated, extraRedundantCheck);

  final List<ContextKeyExpression> expr;
  ContextKeyExpression? _negated;

  @override
  ContextKeyExprType get type => ContextKeyExprType.and;

  @override
  int cmp(ContextKeyExpression other) {
    if (other.type != type) return type.index - other.type.index;
    final o = other as ContextKeyAndExpr;
    if (expr.length < o.expr.length) return -1;
    if (expr.length > o.expr.length) return 1;
    for (var i = 0; i < expr.length; i++) {
      final r = expr[i].cmp(o.expr[i]);
      if (r != 0) return r;
    }
    return 0;
  }

  @override
  bool equals(ContextKeyExpression other) {
    if (other is! ContextKeyAndExpr) return false;
    if (expr.length != other.expr.length) return false;
    for (var i = 0; i < expr.length; i++) {
      if (!expr[i].equals(other.expr[i])) return false;
    }
    return true;
  }

  @override
  ContextKeyExpression? substituteConstants() {
    final exprArr = _eliminateConstantsInArray(expr);
    if (identical(exprArr, expr)) return this;
    return ContextKeyAndExpr.create(exprArr, _negated, false);
  }

  @override
  bool evaluate(ContextKeyLookup context) {
    for (final e in expr) {
      if (!e.evaluate(context)) return false;
    }
    return true;
  }

  static ContextKeyExpression? _normalizeArr(
    List<ContextKeyExpression?> arr,
    ContextKeyExpression? negated,
    bool extraRedundantCheck,
  ) {
    final expr = <ContextKeyExpression>[];
    var hasTrue = false;
    for (final e in arr) {
      if (e == null) continue;
      if (e.type == ContextKeyExprType.trueExpr) {
        hasTrue = true;
        continue;
      }
      if (e.type == ContextKeyExprType.falseExpr) {
        return ContextKeyFalseExpr.instance;
      }
      if (e is ContextKeyAndExpr) {
        expr.addAll(e.expr);
        continue;
      }
      expr.add(e);
    }
    if (expr.isEmpty && hasTrue) return ContextKeyTrueExpr.instance;
    if (expr.isEmpty) return null;
    if (expr.length == 1) return expr[0];

    _sort(expr);
    for (var i = 1; i < expr.length; i++) {
      if (expr[i - 1].equals(expr[i])) {
        expr.removeAt(i);
        i--;
      }
    }
    if (expr.length == 1) return expr[0];

    // Distribute any OR over the rest: no parentheses in serialized form.
    while (expr.length > 1) {
      final lastElement = expr.last;
      if (lastElement is! ContextKeyOrExpr) break;
      expr.removeLast();
      final secondToLastElement = expr.removeLast();
      final isFinished = expr.isEmpty;
      final resultElement = ContextKeyOrExpr.create(
        [
          for (final el in lastElement.expr)
            ContextKeyAndExpr.create(
              [el, secondToLastElement],
              null,
              extraRedundantCheck,
            ),
        ],
        null,
        isFinished,
      );
      if (resultElement != null) {
        expr.add(resultElement);
        _sort(expr);
      }
    }
    if (expr.length == 1) return expr[0];

    if (extraRedundantCheck) {
      for (var i = 0; i < expr.length; i++) {
        for (var j = i + 1; j < expr.length; j++) {
          if (expr[i].negate().equals(expr[j])) {
            return ContextKeyFalseExpr.instance;
          }
        }
      }
      if (expr.length == 1) return expr[0];
    }
    return ContextKeyAndExpr._(expr, negated);
  }

  @override
  String serialize() => expr.map((e) => e.serialize()).join(' && ');

  @override
  List<String> keys() => [for (final e in expr) ...e.keys()];

  @override
  ContextKeyExpression map(ContextKeyExprMapper mapFnc) =>
      ContextKeyAndExpr._([for (final e in expr) e.map(mapFnc)], null);

  @override
  ContextKeyExpression negate() => _negated ??= ContextKeyOrExpr.create(
    [for (final e in expr) e.negate()],
    this,
    true,
  )!;
}

final class ContextKeyOrExpr extends ContextKeyExpression {
  ContextKeyOrExpr._(this.expr, this._negated);

  static ContextKeyExpression? create(
    List<ContextKeyExpression?> expr,
    ContextKeyExpression? negated,
    bool extraRedundantCheck,
  ) => _normalizeArr(expr, negated, extraRedundantCheck);

  final List<ContextKeyExpression> expr;
  ContextKeyExpression? _negated;

  @override
  ContextKeyExprType get type => ContextKeyExprType.or;

  @override
  int cmp(ContextKeyExpression other) {
    if (other.type != type) return type.index - other.type.index;
    final o = other as ContextKeyOrExpr;
    if (expr.length < o.expr.length) return -1;
    if (expr.length > o.expr.length) return 1;
    for (var i = 0; i < expr.length; i++) {
      final r = expr[i].cmp(o.expr[i]);
      if (r != 0) return r;
    }
    return 0;
  }

  @override
  bool equals(ContextKeyExpression other) {
    if (other is! ContextKeyOrExpr) return false;
    if (expr.length != other.expr.length) return false;
    for (var i = 0; i < expr.length; i++) {
      if (!expr[i].equals(other.expr[i])) return false;
    }
    return true;
  }

  @override
  ContextKeyExpression? substituteConstants() {
    final exprArr = _eliminateConstantsInArray(expr);
    if (identical(exprArr, expr)) return this;
    return ContextKeyOrExpr.create(exprArr, _negated, false);
  }

  @override
  bool evaluate(ContextKeyLookup context) {
    for (final e in expr) {
      if (e.evaluate(context)) return true;
    }
    return false;
  }

  static ContextKeyExpression? _normalizeArr(
    List<ContextKeyExpression?> arr,
    ContextKeyExpression? negated,
    bool extraRedundantCheck,
  ) {
    var expr = <ContextKeyExpression>[];
    var hasFalse = false;
    for (final e in arr) {
      if (e == null) continue;
      if (e.type == ContextKeyExprType.falseExpr) {
        hasFalse = true;
        continue;
      }
      if (e.type == ContextKeyExprType.trueExpr) {
        return ContextKeyTrueExpr.instance;
      }
      if (e is ContextKeyOrExpr) {
        expr = [...expr, ...e.expr];
        continue;
      }
      expr.add(e);
    }
    if (expr.isEmpty && hasFalse) return ContextKeyFalseExpr.instance;
    _sort(expr);
    if (expr.isEmpty) return null;
    if (expr.length == 1) return expr[0];

    for (var i = 1; i < expr.length; i++) {
      if (expr[i - 1].equals(expr[i])) {
        expr.removeAt(i);
        i--;
      }
    }
    if (expr.length == 1) return expr[0];

    if (extraRedundantCheck) {
      for (var i = 0; i < expr.length; i++) {
        for (var j = i + 1; j < expr.length; j++) {
          if (expr[i].negate().equals(expr[j])) {
            return ContextKeyTrueExpr.instance;
          }
        }
      }
      if (expr.length == 1) return expr[0];
    }
    return ContextKeyOrExpr._(expr, negated);
  }

  @override
  String serialize() => expr.map((e) => e.serialize()).join(' || ');

  @override
  List<String> keys() => [for (final e in expr) ...e.keys()];

  @override
  ContextKeyExpression map(ContextKeyExprMapper mapFnc) =>
      ContextKeyOrExpr._([for (final e in expr) e.map(mapFnc)], null);

  @override
  ContextKeyExpression negate() {
    if (_negated case final negated?) return negated;
    final result = [for (final e in expr) e.negate()];
    // No parentheses: distribute the AND over the OR terminals, two at a
    // time.
    while (result.length > 1) {
      final left = result.removeAt(0);
      final right = result.removeAt(0);
      final all = <ContextKeyExpression?>[
        for (final l in _getTerminals(left))
          for (final r in _getTerminals(right))
            ContextKeyAndExpr.create([l, r], null, false),
      ];
      result.insert(0, ContextKeyOrExpr.create(all, null, false)!);
    }
    return _negated = ContextKeyOrExpr.create(result, this, true)!;
  }
}

List<ContextKeyExpression> _getTerminals(ContextKeyExpression node) =>
    node is ContextKeyOrExpr ? node.expr : [node];

/// `implies`: whether it is provable that [p] implies [q].
bool implies(ContextKeyExpression p, ContextKeyExpression q) {
  if (p.type == ContextKeyExprType.falseExpr ||
      q.type == ContextKeyExprType.trueExpr) {
    return true;
  }
  if (p is ContextKeyOrExpr) {
    if (q is ContextKeyOrExpr) return _allElementsIncluded(p.expr, q.expr);
    return false;
  }
  if (q is ContextKeyOrExpr) {
    for (final element in q.expr) {
      if (implies(p, element)) return true;
    }
    return false;
  }
  if (p is ContextKeyAndExpr) {
    if (q is ContextKeyAndExpr) return _allElementsIncluded(q.expr, p.expr);
    for (final element in p.expr) {
      if (implies(element, q)) return true;
    }
    return false;
  }
  return p.equals(q);
}

/// Whether every element of [p] is in [q] (both sorted).
bool _allElementsIncluded(
  List<ContextKeyExpression> p,
  List<ContextKeyExpression> q,
) {
  var pIndex = 0;
  var qIndex = 0;
  while (pIndex < p.length && qIndex < q.length) {
    final c = p[pIndex].cmp(q[qIndex]);
    if (c < 0) return false;
    if (c == 0) {
      pIndex++;
      qIndex++;
    } else {
      qIndex++;
    }
  }
  return pIndex == p.length;
}
