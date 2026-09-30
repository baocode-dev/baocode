/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Subset of VS Code src/vs/base/common/json.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971: the scanner (`createScanner`),
// `visit`, `parse` and `getNodeType`, with their enums and options. The
// tree API (`parseTree`, `getLocation`, `findNodeAtLocation`, ...) is not
// ported.
// Deviations: TypeScript const enums become integer constants (camelCase);
// reading past the end of the text yields -1 where JavaScript's `charCodeAt`
// yields NaN (both compare unequal to every character); objects parse to
// insertion-ordered `Map<String, Object?>`, arrays to `List<Object?>`, numbers
// to `num` via `jsonDecode` in place of `JSON.parse` (so `1` is an `int`).

import 'dart:convert' as convert;

abstract final class ScanError {
  static const int none = 0;
  static const int unexpectedEndOfComment = 1;
  static const int unexpectedEndOfString = 2;
  static const int unexpectedEndOfNumber = 3;
  static const int invalidUnicode = 4;
  static const int invalidEscapeCharacter = 5;
  static const int invalidCharacter = 6;
}

abstract final class SyntaxKind {
  static const int openBraceToken = 1;
  static const int closeBraceToken = 2;
  static const int openBracketToken = 3;
  static const int closeBracketToken = 4;
  static const int commaToken = 5;
  static const int colonToken = 6;
  static const int nullKeyword = 7;
  static const int trueKeyword = 8;
  static const int falseKeyword = 9;
  static const int stringLiteral = 10;
  static const int numericLiteral = 11;
  static const int lineCommentTrivia = 12;
  static const int blockCommentTrivia = 13;
  static const int lineBreakTrivia = 14;
  static const int trivia = 15;
  static const int unknown = 16;
  static const int eof = 17;
}

/// The scanner object, representing a JSON scanner at a position in the
/// input string.
abstract interface class JSONScanner {
  /// Sets the scan position to a new offset. A call to [scan] is needed to
  /// get the first token.
  void setPosition(int pos);

  /// Reads the next token. Returns the token code ([SyntaxKind]).
  int scan();

  /// The current scan position, which is after the last read token.
  int getPosition();

  /// The last read token ([SyntaxKind]).
  int getToken();

  /// The last read token value. For strings it is the decoded string
  /// content; for numbers and keywords, their text.
  String getTokenValue();

  /// The start offset of the last read token.
  int getTokenOffset();

  /// The length of the last read token.
  int getTokenLength();

  /// An error code ([ScanError]) of the last scan.
  int getTokenError();
}

class ParseError {
  const ParseError({
    required this.error,
    required this.offset,
    required this.length,
  });

  /// A [ParseErrorCode].
  final int error;
  final int offset;
  final int length;

  @override
  bool operator ==(Object other) =>
      other is ParseError &&
      other.error == error &&
      other.offset == offset &&
      other.length == length;

  @override
  int get hashCode => Object.hash(error, offset, length);

  @override
  String toString() =>
      'ParseError(error: $error, offset: $offset, length: $length)';
}

abstract final class ParseErrorCode {
  static const int invalidSymbol = 1;
  static const int invalidNumberFormat = 2;
  static const int propertyNameExpected = 3;
  static const int valueExpected = 4;
  static const int colonExpected = 5;
  static const int commaExpected = 6;
  static const int closeBraceExpected = 7;
  static const int closeBracketExpected = 8;
  static const int endOfFileExpected = 9;
  static const int invalidCommentToken = 10;
  static const int unexpectedEndOfComment = 11;
  static const int unexpectedEndOfString = 12;
  static const int unexpectedEndOfNumber = 13;
  static const int invalidUnicode = 14;
  static const int invalidEscapeCharacter = 15;
  static const int invalidCharacter = 16;
}

/// `'object' | 'array' | 'property' | 'string' | 'number' | 'boolean' |
/// 'null'`.
typedef NodeType = String;

class ParseOptions {
  const ParseOptions({
    this.disallowComments = false,
    this.allowTrailingComma = false,
    this.allowEmptyContent = false,
  });

  final bool disallowComments;
  final bool allowTrailingComma;
  final bool allowEmptyContent;

  // ignore: constant_identifier_names
  static const DEFAULT = ParseOptions(allowTrailingComma: true);
}

/// Callbacks of [visit]. Offsets and lengths locate the token in the text.
class JSONVisitor {
  const JSONVisitor({
    this.onObjectBegin,
    this.onObjectProperty,
    this.onObjectEnd,
    this.onArrayBegin,
    this.onArrayEnd,
    this.onLiteralValue,
    this.onSeparator,
    this.onComment,
    this.onError,
  });

  /// An open brace: an object starts.
  final void Function(int offset, int length)? onObjectBegin;

  /// A property; offset and length locate the property name.
  final void Function(String property, int offset, int length)?
  onObjectProperty;

  /// A closing brace: an object is complete.
  final void Function(int offset, int length)? onObjectEnd;

  /// An open bracket: an array starts.
  final void Function(int offset, int length)? onArrayBegin;

  /// A closing bracket: an array is complete.
  final void Function(int offset, int length)? onArrayEnd;

  /// A literal value (string, number, boolean or null).
  final void Function(Object? value, int offset, int length)? onLiteralValue;

  /// A comma or colon separator.
  final void Function(String character, int offset, int length)? onSeparator;

  /// When comments are allowed, a line or block comment.
  final void Function(int offset, int length)? onComment;

  /// An error ([ParseErrorCode]).
  final void Function(int error, int offset, int length)? onError;
}

/// Creates a JSON scanner on the given text. If [ignoreTrivia] is set,
/// whitespace and comments are skipped.
JSONScanner createScanner(String text, [bool ignoreTrivia = false]) =>
    _Scanner(text, ignoreTrivia);

class _Scanner implements JSONScanner {
  _Scanner(this.text, this.ignoreTrivia) : len = text.length;

  final String text;
  final bool ignoreTrivia;
  final int len;

  int pos = 0;
  String value = '';
  int tokenOffset = 0;
  int token = SyntaxKind.unknown;
  int scanError = ScanError.none;

  /// JavaScript's `charCodeAt`, with -1 in place of NaN past the end.
  int _charCodeAt(int index) =>
      index >= 0 && index < len ? text.codeUnitAt(index) : -1;

  /// JavaScript's `substring`, which clamps its bounds to the text. Upstream
  /// starts a comment's value one character before its slash, so at offset 0
  /// the start is -1.
  String _substring(int start, int end) =>
      text.substring(start.clamp(0, len), end.clamp(0, len));

  int scanHexDigits(int count) {
    var digits = 0;
    var hexValue = 0;
    while (digits < count) {
      final ch = _charCodeAt(pos);
      if (ch >= _CharacterCodes.digit0 && ch <= _CharacterCodes.digit9) {
        hexValue = hexValue * 16 + ch - _CharacterCodes.digit0;
      } else if (ch >= _CharacterCodes.upperA && ch <= _CharacterCodes.upperF) {
        hexValue = hexValue * 16 + ch - _CharacterCodes.upperA + 10;
      } else if (ch >= _CharacterCodes.a && ch <= _CharacterCodes.f) {
        hexValue = hexValue * 16 + ch - _CharacterCodes.a + 10;
      } else {
        break;
      }
      pos++;
      digits++;
    }
    if (digits < count) {
      hexValue = -1;
    }
    return hexValue;
  }

  @override
  void setPosition(int newPosition) {
    pos = newPosition;
    value = '';
    tokenOffset = 0;
    token = SyntaxKind.unknown;
    scanError = ScanError.none;
  }

  String scanNumber() {
    final start = pos;
    if (_charCodeAt(pos) == _CharacterCodes.digit0) {
      pos++;
    } else {
      pos++;
      while (pos < len && _isDigit(_charCodeAt(pos))) {
        pos++;
      }
    }
    if (pos < len && _charCodeAt(pos) == _CharacterCodes.dot) {
      pos++;
      if (pos < len && _isDigit(_charCodeAt(pos))) {
        pos++;
        while (pos < len && _isDigit(_charCodeAt(pos))) {
          pos++;
        }
      } else {
        scanError = ScanError.unexpectedEndOfNumber;
        return text.substring(start, pos);
      }
    }
    var end = pos;
    if (pos < len &&
        (_charCodeAt(pos) == _CharacterCodes.upperE ||
            _charCodeAt(pos) == _CharacterCodes.e)) {
      pos++;
      // Upstream's precedence: `(pos < length && ch === plus) || ch === minus`.
      if (pos < len && _charCodeAt(pos) == _CharacterCodes.plus ||
          _charCodeAt(pos) == _CharacterCodes.minus) {
        pos++;
      }
      if (pos < len && _isDigit(_charCodeAt(pos))) {
        pos++;
        while (pos < len && _isDigit(_charCodeAt(pos))) {
          pos++;
        }
        end = pos;
      } else {
        scanError = ScanError.unexpectedEndOfNumber;
      }
    }
    return text.substring(start, end);
  }

  String scanString() {
    final result = StringBuffer();
    var start = pos;

    while (true) {
      if (pos >= len) {
        result.write(text.substring(start, pos));
        scanError = ScanError.unexpectedEndOfString;
        break;
      }
      final ch = _charCodeAt(pos);
      if (ch == _CharacterCodes.doubleQuote) {
        result.write(text.substring(start, pos));
        pos++;
        break;
      }
      if (ch == _CharacterCodes.backslash) {
        result.write(text.substring(start, pos));
        pos++;
        if (pos >= len) {
          scanError = ScanError.unexpectedEndOfString;
          break;
        }
        final ch2 = _charCodeAt(pos++);
        switch (ch2) {
          case _CharacterCodes.doubleQuote:
            result.write('"');
          case _CharacterCodes.backslash:
            result.write('\\');
          case _CharacterCodes.slash:
            result.write('/');
          case _CharacterCodes.b:
            result.write('\b');
          case _CharacterCodes.f:
            result.write('\f');
          case _CharacterCodes.n:
            result.write('\n');
          case _CharacterCodes.r:
            result.write('\r');
          case _CharacterCodes.t:
            result.write('\t');
          case _CharacterCodes.u:
            final ch3 = scanHexDigits(4);
            if (ch3 >= 0) {
              result.writeCharCode(ch3);
            } else {
              scanError = ScanError.invalidUnicode;
            }
          default:
            scanError = ScanError.invalidEscapeCharacter;
        }
        start = pos;
        continue;
      }
      if (ch >= 0 && ch <= 0x1F) {
        if (_isLineBreak(ch)) {
          result.write(text.substring(start, pos));
          scanError = ScanError.unexpectedEndOfString;
          break;
        } else {
          scanError = ScanError.invalidCharacter;
          // mark as error but continue with string
        }
      }
      pos++;
    }
    return result.toString();
  }

  int scanNext() {
    value = '';
    scanError = ScanError.none;

    tokenOffset = pos;

    if (pos >= len) {
      // at the end
      tokenOffset = len;
      return token = SyntaxKind.eof;
    }

    var code = _charCodeAt(pos);
    // trivia: whitespace
    if (_isWhitespace(code)) {
      final buffer = StringBuffer();
      do {
        pos++;
        buffer.writeCharCode(code);
        code = _charCodeAt(pos);
      } while (_isWhitespace(code));
      value = buffer.toString();
      return token = SyntaxKind.trivia;
    }

    // trivia: newlines
    if (_isLineBreak(code)) {
      pos++;
      value += String.fromCharCode(code);
      if (code == _CharacterCodes.carriageReturn &&
          _charCodeAt(pos) == _CharacterCodes.lineFeed) {
        pos++;
        value += '\n';
      }
      return token = SyntaxKind.lineBreakTrivia;
    }

    switch (code) {
      // tokens: []{}:,
      case _CharacterCodes.openBrace:
        pos++;
        return token = SyntaxKind.openBraceToken;
      case _CharacterCodes.closeBrace:
        pos++;
        return token = SyntaxKind.closeBraceToken;
      case _CharacterCodes.openBracket:
        pos++;
        return token = SyntaxKind.openBracketToken;
      case _CharacterCodes.closeBracket:
        pos++;
        return token = SyntaxKind.closeBracketToken;
      case _CharacterCodes.colon:
        pos++;
        return token = SyntaxKind.colonToken;
      case _CharacterCodes.comma:
        pos++;
        return token = SyntaxKind.commaToken;

      // strings
      case _CharacterCodes.doubleQuote:
        pos++;
        value = scanString();
        return token = SyntaxKind.stringLiteral;

      // comments
      case _CharacterCodes.slash:
        final start = pos - 1;
        // Single-line comment
        if (_charCodeAt(pos + 1) == _CharacterCodes.slash) {
          pos += 2;

          while (pos < len) {
            if (_isLineBreak(_charCodeAt(pos))) {
              break;
            }
            pos++;
          }
          value = _substring(start, pos);
          return token = SyntaxKind.lineCommentTrivia;
        }

        // Multi-line comment
        if (_charCodeAt(pos + 1) == _CharacterCodes.asterisk) {
          pos += 2;

          final safeLength = len - 1; // For lookahead.
          var commentClosed = false;
          while (pos < safeLength) {
            final ch = _charCodeAt(pos);

            if (ch == _CharacterCodes.asterisk &&
                _charCodeAt(pos + 1) == _CharacterCodes.slash) {
              pos += 2;
              commentClosed = true;
              break;
            }
            pos++;
          }

          if (!commentClosed) {
            pos++;
            scanError = ScanError.unexpectedEndOfComment;
          }

          value = _substring(start, pos);
          return token = SyntaxKind.blockCommentTrivia;
        }
        // just a single slash
        value += String.fromCharCode(code);
        pos++;
        return token = SyntaxKind.unknown;

      // numbers
      case _CharacterCodes.minus:
        value += String.fromCharCode(code);
        pos++;
        if (pos == len || !_isDigit(_charCodeAt(pos))) {
          return token = SyntaxKind.unknown;
        }
        // found a minus, followed by a number so
        // we fall through to proceed with scanning
        // numbers
        value += scanNumber();
        return token = SyntaxKind.numericLiteral;
      case _CharacterCodes.digit0:
      case _CharacterCodes.digit1:
      case _CharacterCodes.digit2:
      case _CharacterCodes.digit3:
      case _CharacterCodes.digit4:
      case _CharacterCodes.digit5:
      case _CharacterCodes.digit6:
      case _CharacterCodes.digit7:
      case _CharacterCodes.digit8:
      case _CharacterCodes.digit9:
        value += scanNumber();
        return token = SyntaxKind.numericLiteral;
      // literals and unknown symbols
      default:
        // is a literal? Read the full word.
        while (pos < len && _isUnknownContentCharacter(code)) {
          pos++;
          code = _charCodeAt(pos);
        }
        if (tokenOffset != pos) {
          value = text.substring(tokenOffset, pos);
          // keywords: true, false, null
          switch (value) {
            case 'true':
              return token = SyntaxKind.trueKeyword;
            case 'false':
              return token = SyntaxKind.falseKeyword;
            case 'null':
              return token = SyntaxKind.nullKeyword;
          }
          return token = SyntaxKind.unknown;
        }
        // some
        value += String.fromCharCode(code);
        pos++;
        return token = SyntaxKind.unknown;
    }
  }

  bool _isUnknownContentCharacter(int code) {
    if (_isWhitespace(code) || _isLineBreak(code)) {
      return false;
    }
    switch (code) {
      case _CharacterCodes.closeBrace:
      case _CharacterCodes.closeBracket:
      case _CharacterCodes.openBrace:
      case _CharacterCodes.openBracket:
      case _CharacterCodes.doubleQuote:
      case _CharacterCodes.colon:
      case _CharacterCodes.comma:
      case _CharacterCodes.slash:
        return false;
    }
    return true;
  }

  int scanNextNonTrivia() {
    int result;
    do {
      result = scanNext();
    } while (result >= SyntaxKind.lineCommentTrivia &&
        result <= SyntaxKind.trivia);
    return result;
  }

  @override
  int scan() => ignoreTrivia ? scanNextNonTrivia() : scanNext();

  @override
  int getPosition() => pos;

  @override
  int getToken() => token;

  @override
  String getTokenValue() => value;

  @override
  int getTokenOffset() => tokenOffset;

  @override
  int getTokenLength() => pos - tokenOffset;

  @override
  int getTokenError() => scanError;
}

bool _isWhitespace(int ch) =>
    ch == _CharacterCodes.space ||
    ch == _CharacterCodes.tab ||
    ch == _CharacterCodes.verticalTab ||
    ch == _CharacterCodes.formFeed ||
    ch == _CharacterCodes.nonBreakingSpace ||
    ch == _CharacterCodes.ogham ||
    ch >= _CharacterCodes.enQuad && ch <= _CharacterCodes.zeroWidthSpace ||
    ch == _CharacterCodes.narrowNoBreakSpace ||
    ch == _CharacterCodes.mathematicalSpace ||
    ch == _CharacterCodes.ideographicSpace ||
    ch == _CharacterCodes.byteOrderMark;

bool _isLineBreak(int ch) =>
    ch == _CharacterCodes.lineFeed ||
    ch == _CharacterCodes.carriageReturn ||
    ch == _CharacterCodes.lineSeparator ||
    ch == _CharacterCodes.paragraphSeparator;

bool _isDigit(int ch) =>
    ch >= _CharacterCodes.digit0 && ch <= _CharacterCodes.digit9;

/// The subset of upstream's `CharacterCodes` the scanner uses.
abstract final class _CharacterCodes {
  static const int lineFeed = 0x0A; // \n
  static const int carriageReturn = 0x0D; // \r
  static const int lineSeparator = 0x2028;
  static const int paragraphSeparator = 0x2029;

  static const int space = 0x0020;
  static const int nonBreakingSpace = 0x00A0;
  static const int enQuad = 0x2000;
  static const int zeroWidthSpace = 0x200B;
  static const int narrowNoBreakSpace = 0x202F;
  static const int ideographicSpace = 0x3000;
  static const int mathematicalSpace = 0x205F;
  static const int ogham = 0x1680;

  static const int digit0 = 0x30;
  static const int digit1 = 0x31;
  static const int digit2 = 0x32;
  static const int digit3 = 0x33;
  static const int digit4 = 0x34;
  static const int digit5 = 0x35;
  static const int digit6 = 0x36;
  static const int digit7 = 0x37;
  static const int digit8 = 0x38;
  static const int digit9 = 0x39;

  static const int a = 0x61;
  static const int b = 0x62;
  static const int e = 0x65;
  static const int f = 0x66;
  static const int n = 0x6E;
  static const int r = 0x72;
  static const int t = 0x74;
  static const int u = 0x75;

  static const int upperA = 0x41;
  static const int upperE = 0x45;
  static const int upperF = 0x46;

  static const int asterisk = 0x2A; // *
  static const int backslash = 0x5C; // \
  static const int closeBrace = 0x7D; // }
  static const int closeBracket = 0x5D; // ]
  static const int colon = 0x3A; // :
  static const int comma = 0x2C; // ,
  static const int dot = 0x2E; // .
  static const int doubleQuote = 0x22; // "
  static const int minus = 0x2D; // -
  static const int openBrace = 0x7B; // {
  static const int openBracket = 0x5B; // [
  static const int plus = 0x2B; // +
  static const int slash = 0x2F; // /

  static const int formFeed = 0x0C; // \f
  static const int byteOrderMark = 0xFEFF;
  static const int tab = 0x09; // \t
  static const int verticalTab = 0x0B; // \v
}

/// Parses the given text and returns the object the JSON content represents.
/// On invalid input, the parser tries to be as fault tolerant as possible,
/// but still returns a result. Therefore always check [errors] to find out if
/// the input was valid.
Object? parse(
  String text, [
  List<ParseError>? errors,
  ParseOptions options = ParseOptions.DEFAULT,
]) {
  String? currentProperty;
  Object currentParent = <Object?>[];
  final previousParents = <Object>[];

  void onValue(Object? value) {
    final parent = currentParent;
    if (parent is List<Object?>) {
      parent.add(value);
    } else if (currentProperty != null) {
      (parent as Map<String, Object?>)[currentProperty!] = value;
    }
  }

  final visitor = JSONVisitor(
    onObjectBegin: (_, _) {
      final object = <String, Object?>{};
      onValue(object);
      previousParents.add(currentParent);
      currentParent = object;
      currentProperty = null;
    },
    onObjectProperty: (name, _, _) {
      currentProperty = name;
    },
    onObjectEnd: (_, _) {
      currentParent = previousParents.removeLast();
    },
    onArrayBegin: (_, _) {
      final array = <Object?>[];
      onValue(array);
      previousParents.add(currentParent);
      currentParent = array;
      currentProperty = null;
    },
    onArrayEnd: (_, _) {
      currentParent = previousParents.removeLast();
    },
    onLiteralValue: (value, _, _) => onValue(value),
    onError: (error, offset, length) {
      errors?.add(ParseError(error: error, offset: offset, length: length));
    },
  );
  visit(text, visitor, options);
  final root = currentParent as List<Object?>;
  return root.isEmpty ? null : root[0];
}

/// Parses the given text and invokes the visitor functions for each object,
/// array and literal reached.
bool visit(
  String text,
  JSONVisitor visitor, [
  ParseOptions options = ParseOptions.DEFAULT,
]) {
  final scanner = createScanner(text, false);

  void Function() toNoArgVisit(void Function(int, int)? visitFunction) =>
      visitFunction == null
      ? () {}
      : () => visitFunction(scanner.getTokenOffset(), scanner.getTokenLength());
  void Function(T) toOneArgVisit<T>(
    void Function(T, int, int)? visitFunction,
  ) => visitFunction == null
      ? (_) {}
      : (arg) => visitFunction(
          arg,
          scanner.getTokenOffset(),
          scanner.getTokenLength(),
        );

  final onObjectBegin = toNoArgVisit(visitor.onObjectBegin),
      onObjectProperty = toOneArgVisit<String>(visitor.onObjectProperty),
      onObjectEnd = toNoArgVisit(visitor.onObjectEnd),
      onArrayBegin = toNoArgVisit(visitor.onArrayBegin),
      onArrayEnd = toNoArgVisit(visitor.onArrayEnd),
      onLiteralValue = toOneArgVisit<Object?>(visitor.onLiteralValue),
      onSeparator = toOneArgVisit<String>(visitor.onSeparator),
      onComment = toNoArgVisit(visitor.onComment),
      onError = toOneArgVisit<int>(visitor.onError);

  final disallowComments = options.disallowComments;
  final allowTrailingComma = options.allowTrailingComma;

  late final void Function(
    int error, [
    List<int> skipUntilAfter,
    List<int> skipUntil,
  ])
  handleError;

  int scanNext() {
    while (true) {
      final token = scanner.scan();
      switch (scanner.getTokenError()) {
        case ScanError.invalidUnicode:
          handleError(ParseErrorCode.invalidUnicode);
        case ScanError.invalidEscapeCharacter:
          handleError(ParseErrorCode.invalidEscapeCharacter);
        case ScanError.unexpectedEndOfNumber:
          handleError(ParseErrorCode.unexpectedEndOfNumber);
        case ScanError.unexpectedEndOfComment:
          if (!disallowComments) {
            handleError(ParseErrorCode.unexpectedEndOfComment);
          }
        case ScanError.unexpectedEndOfString:
          handleError(ParseErrorCode.unexpectedEndOfString);
        case ScanError.invalidCharacter:
          handleError(ParseErrorCode.invalidCharacter);
      }
      switch (token) {
        case SyntaxKind.lineCommentTrivia:
        case SyntaxKind.blockCommentTrivia:
          if (disallowComments) {
            handleError(ParseErrorCode.invalidCommentToken);
          } else {
            onComment();
          }
        case SyntaxKind.unknown:
          handleError(ParseErrorCode.invalidSymbol);
        case SyntaxKind.trivia:
        case SyntaxKind.lineBreakTrivia:
          break;
        default:
          return token;
      }
    }
  }

  handleError =
      (
        int error, [
        List<int> skipUntilAfter = const [],
        List<int> skipUntil = const [],
      ]) {
        onError(error);
        if (skipUntilAfter.length + skipUntil.length > 0) {
          var token = scanner.getToken();
          while (token != SyntaxKind.eof) {
            if (skipUntilAfter.contains(token)) {
              scanNext();
              break;
            } else if (skipUntil.contains(token)) {
              break;
            }
            token = scanNext();
          }
        }
      };

  bool parseString(bool isValue) {
    final value = scanner.getTokenValue();
    if (isValue) {
      onLiteralValue(value);
    } else {
      onObjectProperty(value);
    }
    scanNext();
    return true;
  }

  bool parseLiteral() {
    switch (scanner.getToken()) {
      case SyntaxKind.numericLiteral:
        Object? value = 0;
        try {
          value = convert.jsonDecode(scanner.getTokenValue());
          if (value is! num) {
            handleError(ParseErrorCode.invalidNumberFormat);
            value = 0;
          }
        } on FormatException {
          handleError(ParseErrorCode.invalidNumberFormat);
        }
        onLiteralValue(value);
      case SyntaxKind.nullKeyword:
        onLiteralValue(null);
      case SyntaxKind.trueKeyword:
        onLiteralValue(true);
      case SyntaxKind.falseKeyword:
        onLiteralValue(false);
      default:
        return false;
    }
    scanNext();
    return true;
  }

  late final bool Function() parseValue;

  bool parseProperty() {
    if (scanner.getToken() != SyntaxKind.stringLiteral) {
      handleError(ParseErrorCode.propertyNameExpected, const [], const [
        SyntaxKind.closeBraceToken,
        SyntaxKind.commaToken,
      ]);
      return false;
    }
    parseString(false);
    if (scanner.getToken() == SyntaxKind.colonToken) {
      onSeparator(':');
      scanNext(); // consume colon

      if (!parseValue()) {
        handleError(ParseErrorCode.valueExpected, const [], const [
          SyntaxKind.closeBraceToken,
          SyntaxKind.commaToken,
        ]);
      }
    } else {
      handleError(ParseErrorCode.colonExpected, const [], const [
        SyntaxKind.closeBraceToken,
        SyntaxKind.commaToken,
      ]);
    }
    return true;
  }

  bool parseObject() {
    onObjectBegin();
    scanNext(); // consume open brace

    var needsComma = false;
    while (scanner.getToken() != SyntaxKind.closeBraceToken &&
        scanner.getToken() != SyntaxKind.eof) {
      if (scanner.getToken() == SyntaxKind.commaToken) {
        if (!needsComma) {
          handleError(ParseErrorCode.valueExpected, const [], const []);
        }
        onSeparator(',');
        scanNext(); // consume comma
        if (scanner.getToken() == SyntaxKind.closeBraceToken &&
            allowTrailingComma) {
          break;
        }
      } else if (needsComma) {
        handleError(ParseErrorCode.commaExpected, const [], const []);
      }
      if (!parseProperty()) {
        handleError(ParseErrorCode.valueExpected, const [], const [
          SyntaxKind.closeBraceToken,
          SyntaxKind.commaToken,
        ]);
      }
      needsComma = true;
    }
    onObjectEnd();
    if (scanner.getToken() != SyntaxKind.closeBraceToken) {
      handleError(ParseErrorCode.closeBraceExpected, const [
        SyntaxKind.closeBraceToken,
      ], const []);
    } else {
      scanNext(); // consume close brace
    }
    return true;
  }

  bool parseArray() {
    onArrayBegin();
    scanNext(); // consume open bracket

    var needsComma = false;
    while (scanner.getToken() != SyntaxKind.closeBracketToken &&
        scanner.getToken() != SyntaxKind.eof) {
      if (scanner.getToken() == SyntaxKind.commaToken) {
        if (!needsComma) {
          handleError(ParseErrorCode.valueExpected, const [], const []);
        }
        onSeparator(',');
        scanNext(); // consume comma
        if (scanner.getToken() == SyntaxKind.closeBracketToken &&
            allowTrailingComma) {
          break;
        }
      } else if (needsComma) {
        handleError(ParseErrorCode.commaExpected, const [], const []);
      }
      if (!parseValue()) {
        handleError(ParseErrorCode.valueExpected, const [], const [
          SyntaxKind.closeBracketToken,
          SyntaxKind.commaToken,
        ]);
      }
      needsComma = true;
    }
    onArrayEnd();
    if (scanner.getToken() != SyntaxKind.closeBracketToken) {
      handleError(ParseErrorCode.closeBracketExpected, const [
        SyntaxKind.closeBracketToken,
      ], const []);
    } else {
      scanNext(); // consume close bracket
    }
    return true;
  }

  parseValue = () {
    switch (scanner.getToken()) {
      case SyntaxKind.openBracketToken:
        return parseArray();
      case SyntaxKind.openBraceToken:
        return parseObject();
      case SyntaxKind.stringLiteral:
        return parseString(true);
      default:
        return parseLiteral();
    }
  };

  scanNext();
  if (scanner.getToken() == SyntaxKind.eof) {
    if (options.allowEmptyContent) {
      return true;
    }
    handleError(ParseErrorCode.valueExpected, const [], const []);
    return false;
  }
  if (!parseValue()) {
    handleError(ParseErrorCode.valueExpected, const [], const []);
    return false;
  }
  if (scanner.getToken() != SyntaxKind.eof) {
    handleError(ParseErrorCode.endOfFileExpected, const [], const []);
  }
  return true;
}

/// The JSON node type of a parsed value.
NodeType getNodeType(Object? value) {
  if (value is bool) return 'boolean';
  if (value is num) return 'number';
  if (value is String) return 'string';
  if (value is List) return 'array';
  if (value is Map) return 'object';
  return 'null';
}
