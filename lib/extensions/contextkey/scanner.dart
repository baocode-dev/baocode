/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The tokens of a context key (`when`) expression.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/platform/contextkey/common/scanner.ts.
//
// Deviations:
// - Offsets are UTF-16 code unit offsets, as upstream's (Dart strings index
//   the same way).
// - The hints are English only (upstream localizes them); they are shown to
//   extension authors, not users.

/// `TokenType`.
enum TokenType {
  lParen,
  rParen,
  neg,
  eq,
  notEq,
  lt,
  ltEq,
  gt,
  gtEq,
  regexOp,
  regexStr,
  trueKeyword,
  falseKeyword,
  inKeyword,
  notKeyword,
  and,
  or,
  str,
  quotedStr,
  error,
  eof,
}

/// `Token`: [lexeme] for [TokenType.regexStr], [TokenType.str],
/// [TokenType.quotedStr] and [TokenType.error]; [isTripleEq] for `===` and
/// `!==`.
final class Token {
  const Token(this.type, this.offset, {this.lexeme, this.isTripleEq = false});

  final TokenType type;
  final int offset;
  final String? lexeme;
  final bool isTripleEq;

  @override
  bool operator ==(Object other) =>
      other is Token &&
      other.type == type &&
      other.offset == offset &&
      other.lexeme == lexeme &&
      other.isTripleEq == isTripleEq;

  @override
  int get hashCode => Object.hash(type, offset, lexeme, isTripleEq);

  @override
  String toString() =>
      'Token($type, $offset${lexeme == null ? '' : ', $lexeme'})';
}

/// `LexingError`.
final class LexingError {
  const LexingError({
    required this.offset,
    required this.lexeme,
    this.additionalInfo,
  });

  final int offset;
  final String lexeme;
  final String? additionalInfo;
}

String? _hintDidYouMean(List<String> meant) => switch (meant.length) {
  1 => 'Did you mean ${meant[0]}?',
  2 => 'Did you mean ${meant[0]} or ${meant[1]}?',
  3 => 'Did you mean ${meant[0]}, ${meant[1]} or ${meant[2]}?',
  _ => null,
};

const _hintDidYouForgetToOpenOrCloseQuote =
    'Did you forget to open or close the quote?';
const _hintDidYouForgetToEscapeSlash =
    "Did you forget to escape the '/' (slash) character? Put two backslashes "
    r"before it to escape, e.g., '\\/'.";

const _openParen = 0x28;
const _closeParen = 0x29;
const _exclamationMark = 0x21;
const _singleQuote = 0x27;
const _slash = 0x2f;
const _equals = 0x3d;
const _tilde = 0x7e;
const _lessThan = 0x3c;
const _greaterThan = 0x3e;
const _ampersand = 0x26;
const _pipe = 0x7c;
const _space = 0x20;
const _carriageReturn = 0x0d;
const _tab = 0x09;
const _lineFeed = 0x0a;
const _noBreakSpace = 0xa0;
const _openSquareBracket = 0x5b;
const _closeSquareBracket = 0x5d;
const _backslash = 0x5c;

/// `Scanner`.
final class Scanner {
  static String getLexeme(Token token) => switch (token.type) {
    TokenType.lParen => '(',
    TokenType.rParen => ')',
    TokenType.neg => '!',
    TokenType.eq => token.isTripleEq ? '===' : '==',
    TokenType.notEq => token.isTripleEq ? '!==' : '!=',
    TokenType.lt => '<',
    TokenType.ltEq => '<=',
    TokenType.gt => '>',
    TokenType.gtEq => '>=',
    TokenType.regexOp => '=~',
    TokenType.regexStr => token.lexeme!,
    TokenType.trueKeyword => 'true',
    TokenType.falseKeyword => 'false',
    TokenType.inKeyword => 'in',
    TokenType.notKeyword => 'not',
    TokenType.and => '&&',
    TokenType.or => '||',
    TokenType.str => token.lexeme!,
    TokenType.quotedStr => token.lexeme!,
    TokenType.error => token.lexeme!,
    TokenType.eof => 'EOF',
  };

  static final _regexFlags = {for (final c in 'igsmyu'.codeUnits) c};

  static const _keywords = {
    'not': TokenType.notKeyword,
    'in': TokenType.inKeyword,
    'false': TokenType.falseKeyword,
    'true': TokenType.trueKeyword,
  };

  String _input = '';
  int _start = 0;
  int _current = 0;
  List<Token> _tokens = [];
  List<LexingError> _errors = [];

  List<LexingError> get errors => List.unmodifiable(_errors);

  Scanner reset(String value) {
    _input = value;
    _start = 0;
    _current = 0;
    _tokens = [];
    _errors = [];
    return this;
  }

  List<Token> scan() {
    while (!_isAtEnd) {
      _start = _current;
      final ch = _advance();
      switch (ch) {
        case _openParen:
          _addToken(TokenType.lParen);
        case _closeParen:
          _addToken(TokenType.rParen);
        case _exclamationMark:
          if (_match(_equals)) {
            final isTripleEq = _match(_equals);
            _tokens.add(Token(TokenType.notEq, _start, isTripleEq: isTripleEq));
          } else {
            _addToken(TokenType.neg);
          }
        case _singleQuote:
          _quotedString();
        case _slash:
          _regex();
        case _equals:
          if (_match(_equals)) {
            final isTripleEq = _match(_equals);
            _tokens.add(Token(TokenType.eq, _start, isTripleEq: isTripleEq));
          } else if (_match(_tilde)) {
            _addToken(TokenType.regexOp);
          } else {
            _error(_hintDidYouMean(['==', '=~']));
          }
        case _lessThan:
          _addToken(_match(_equals) ? TokenType.ltEq : TokenType.lt);
        case _greaterThan:
          _addToken(_match(_equals) ? TokenType.gtEq : TokenType.gt);
        case _ampersand:
          if (_match(_ampersand)) {
            _addToken(TokenType.and);
          } else {
            _error(_hintDidYouMean(['&&']));
          }
        case _pipe:
          if (_match(_pipe)) {
            _addToken(TokenType.or);
          } else {
            _error(_hintDidYouMean(['||']));
          }
        case _space || _carriageReturn || _tab || _lineFeed || _noBreakSpace:
          break;
        default:
          _string();
      }
    }
    _start = _current;
    _addToken(TokenType.eof);
    return List.of(_tokens);
  }

  bool _match(int expected) {
    if (_isAtEnd) return false;
    if (_input.codeUnitAt(_current) != expected) return false;
    _current++;
    return true;
  }

  int _advance() => _input.codeUnitAt(_current++);

  int _peek() => _isAtEnd ? 0 : _input.codeUnitAt(_current);

  void _addToken(TokenType type) => _tokens.add(Token(type, _start));

  void _error([String? additional]) {
    final offset = _start;
    final lexeme = _input.substring(_start, _current);
    _errors.add(
      LexingError(offset: offset, lexeme: lexeme, additionalInfo: additional),
    );
    _tokens.add(Token(TokenType.error, _start, lexeme: lexeme));
  }

  // Upstream: /[a-zA-Z0-9_<>\-\./\\:\*\?\+\[\]\^,#@;"%\$\p{L}-]+/uy
  static final _stringRe = RegExp(
    r'[a-zA-Z0-9_<>\-\./\\:\*\?\+\[\]\^,#@;"%\$\p{L}-]+',
    unicode: true,
  );

  void _string() {
    final match = _stringRe.matchAsPrefix(_input, _start);
    if (match != null) {
      _current = _start + match[0]!.length;
      final lexeme = _input.substring(_start, _current);
      final keyword = _keywords[lexeme];
      if (keyword != null) {
        _addToken(keyword);
      } else {
        _tokens.add(Token(TokenType.str, _start, lexeme: lexeme));
      }
    }
  }

  void _quotedString() {
    while (_peek() != _singleQuote && !_isAtEnd) {
      _advance();
    }
    if (_isAtEnd) {
      _error(_hintDidYouForgetToOpenOrCloseQuote);
      return;
    }
    _advance();
    _tokens.add(
      Token(
        TokenType.quotedStr,
        _start + 1,
        lexeme: _input.substring(_start + 1, _current - 1),
      ),
    );
  }

  void _regex() {
    var p = _current;
    var inEscape = false;
    var inCharacterClass = false;
    while (true) {
      if (p >= _input.length) {
        _current = p;
        _error(_hintDidYouForgetToEscapeSlash);
        return;
      }
      final ch = _input.codeUnitAt(p);
      if (inEscape) {
        inEscape = false;
      } else if (ch == _slash && !inCharacterClass) {
        p++;
        break;
      } else if (ch == _openSquareBracket) {
        inCharacterClass = true;
      } else if (ch == _backslash) {
        inEscape = true;
      } else if (ch == _closeSquareBracket) {
        inCharacterClass = false;
      }
      p++;
    }
    while (p < _input.length && _regexFlags.contains(_input.codeUnitAt(p))) {
      p++;
    }
    _current = p;
    final lexeme = _input.substring(_start, _current);
    _tokens.add(Token(TokenType.regexStr, _start, lexeme: lexeme));
  }

  bool get _isAtEnd => _current >= _input.length;
}
