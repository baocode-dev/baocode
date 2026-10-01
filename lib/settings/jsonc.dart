/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// JSON with comments and trailing commas, as VS Code's settings.json,
// keybindings.json and argv.json are: read leniently, and changed in place
// so that what the user wrote around a change (comments, order, formatting)
// stays as it was.
//
// Adapted from microsoft/node-jsonc-parser 3.3.1: src/impl/scanner.ts
// (`createScanner`), src/impl/parser.ts (`visit`, `parseTree`,
// `findNodeAtLocation`, `getNodeValue`), src/impl/edit.ts (`setProperty`,
// `withFormatting`, `applyEdit`), src/impl/format.ts (`format`) and
// src/main.ts (`applyEdits`); the messages are VS Code's
// (src/vs/base/common/jsonErrorMessages.ts).
//
// Deviations: comments and trailing commas are always allowed, and so is
// empty content (as VS Code reads its settings); a byte order mark reads as
// whitespace; the scanner keeps no line numbers (see
// [JsoncParseError.location]). [modifyJsonc] always formats what it inserts
// (with [JsoncFormatting.detect] when none is given) and returns one edit.
// It appends to a container whose closing bracket has a line of its own on
// a new line above that bracket, after any comments there, instead of after
// the last entry or the opening bracket; inserts before an entry that
// starts its line on a line of its own; removes an entry that has lines of
// its own with those lines, its comma and a comment trailing it, and one
// sharing a line with only its comma, keeping every other comment (not
// laying the lines around it out anew); sets the last of duplicate keys,
// the one a read sees; and does nothing, instead of throwing, when what it
// removes is not there. No `keepLines`, `getInsertionIndex`, visitor API or
// `getLocation`.

import 'dart:convert';
import 'dart:math' as math;

/// The value [text] holds: maps (in the order written), lists, strings,
/// numbers, booleans and null. Comments and trailing commas are fine; empty
/// content (or only comments) is null. What does not parse is reported in
/// [errors] and skipped, as far as possible.
Object? parseJsonc(String text, {List<JsoncParseError>? errors}) =>
    parseJsoncTree(text, errors: errors)?.value;

/// [text]'s syntax tree: where each value is. Null for empty content.
JsoncNode? parseJsoncTree(String text, {List<JsoncParseError>? errors}) =>
    _Parser(text, errors).parse();

/// Why part of a text is not JSON.
enum JsoncErrorCode {
  invalidSymbol('Invalid symbol'),
  invalidNumberFormat('Invalid number format'),
  propertyNameExpected('Property name expected'),
  valueExpected('Value expected'),
  colonExpected('Colon expected'),
  commaExpected('Comma expected'),
  closeBraceExpected('Closing brace expected'),
  closeBracketExpected('Closing bracket expected'),
  endOfFileExpected('End of file expected'),
  unexpectedEndOfComment('Unexpected end of comment'),
  unexpectedEndOfString('Unexpected end of string'),
  unexpectedEndOfNumber('Unexpected end of number'),
  invalidUnicode('Invalid unicode sequence'),
  invalidEscapeCharacter('Invalid escape character'),
  invalidCharacter('Invalid characters in string');

  const JsoncErrorCode(this.message);

  final String message;
}

/// A part of the text [parseJsonc] could not read.
class JsoncParseError {
  JsoncParseError(this.code, this.offset, this.length) : message = code.message;

  final JsoncErrorCode code;
  final String message;
  final int offset;
  final int length;

  /// The 1-based line and column [offset] is at in [text], the text parsed.
  ({int line, int column}) location(String text) {
    var line = 1;
    var lineStart = 0;
    final end = math.min(offset, text.length);
    for (var i = 0; i < end; i++) {
      final char = text.codeUnitAt(i);
      if (char == _lf ||
          (char == _cr &&
              (i + 1 >= text.length || text.codeUnitAt(i + 1) != _lf))) {
        line++;
        lineStart = i + 1;
      }
    }
    return (line: line, column: end - lineStart + 1);
  }

  /// "[message] at line L, column C" for [text], the text parsed.
  String describe(String text) {
    final (:line, :column) = location(text);
    return '$message at line $line, column $column';
  }

  @override
  String toString() => 'JsoncParseError($message, $offset, $length)';
}

/// Replaces [length] characters at [offset] with [content].
class JsoncEdit {
  const JsoncEdit(this.offset, this.length, this.content);

  final int offset;
  final int length;
  final String content;

  @override
  bool operator ==(Object other) =>
      other is JsoncEdit &&
      other.offset == offset &&
      other.length == length &&
      other.content == content;

  @override
  int get hashCode => Object.hash(offset, length, content);

  @override
  String toString() => 'JsoncEdit($offset, $length, ${jsonEncode(content)})';
}

/// How inserted values are laid out.
class JsoncFormatting {
  const JsoncFormatting({
    this.insertSpaces = true,
    this.tabSize = 4,
    this.eol = '\n',
  });

  final bool insertSpaces;
  final int tabSize;

  /// The line break of new lines where the text has none yet; one the text
  /// has wins.
  final String eol;

  /// The indentation and line breaks [text] already uses: tabs when an
  /// indented line starts with one, else the smallest indentation of a
  /// line; 4 spaces and `\n` when it has none.
  static JsoncFormatting detect(String text) {
    var eol = '\n';
    final lineBreak = text.indexOf(RegExp(r'\r\n|\r|\n'));
    if (lineBreak >= 0) {
      eol = text.startsWith('\r\n', lineBreak) ? '\r\n' : text[lineBreak];
    }
    int? smallest;
    for (final line in text.split(RegExp(r'\r\n|\r|\n')).skip(1)) {
      final indent = line.length - line.trimLeft().length;
      if (indent == 0 || indent == line.length) continue;
      // A block comment's continuation (` * …`) says nothing.
      if (line.codeUnitAt(indent) == 0x2A) continue;
      if (line.codeUnitAt(0) == _tab) {
        return JsoncFormatting(insertSpaces: false, eol: eol);
      }
      if (smallest == null || indent < smallest) smallest = indent;
    }
    return JsoncFormatting(tabSize: (smallest ?? 4).clamp(1, 8), eol: eol);
  }
}

/// Sets [path] (keys and array indexes) in [text] to [value], keeping
/// everything else as it is; objects and arrays on the way are created.
/// [remove] deletes it instead (nothing when it is not there). [insert],
/// with an array index last, inserts [value] at that index: `-1` or the
/// array's length appends. Throws a [FormatException] when [path] goes
/// through something that is not an object or array as needed.
List<JsoncEdit> modifyJsonc(
  String text,
  List<Object> path,
  Object? value, {
  bool remove = false,
  bool insert = false,
  JsoncFormatting? formatting,
}) {
  for (final segment in path) {
    if (segment is! String && segment is! int) {
      throw ArgumentError.value(path, 'path', 'keys and indexes only');
    }
  }
  final change = _Modification(
    text,
    formatting ?? JsoncFormatting.detect(text),
  );
  change.plan(path, value, remove: remove, insert: insert);
  return change.result();
}

/// [text] with [edits] made; they must not overlap.
String applyJsoncEdits(String text, List<JsoncEdit> edits) {
  // Stable: edits at one offset are made in the order given.
  final sorted = [for (final (index, edit) in edits.indexed) (index, edit)]
    ..sort((a, b) {
      final byOffset = a.$2.offset - b.$2.offset;
      if (byOffset != 0) return byOffset;
      final byLength = a.$2.length - b.$2.length;
      return byLength != 0 ? byLength : a.$1 - b.$1;
    });
  var lastModifiedOffset = text.length;
  for (final (_, edit) in sorted.reversed) {
    if (edit.offset + edit.length > lastModifiedOffset) {
      throw ArgumentError('Overlapping edit');
    }
    text = _applyEdit(text, edit);
    lastModifiedOffset = edit.offset;
  }
  return text;
}

String _applyEdit(String text, JsoncEdit edit) =>
    text.substring(0, edit.offset) +
    edit.content +
    text.substring(edit.offset + edit.length);

// --- The syntax tree ------------------------------------------------------

enum JsoncNodeType { object, array, property, string, number, boolean, null_ }

/// A value in the text, and where it is (`Node`). A property's children
/// are its key and, unless it is missing, its value.
class JsoncNode {
  JsoncNode._(
    this.type,
    this.offset, {
    this.parent,
    this.length = -1,
    this._value,
  });

  final JsoncNodeType type;
  final int offset;
  int length;
  JsoncNode? parent;
  final List<JsoncNode> children = [];

  /// A property's colon.
  int? colonOffset;

  /// Whether an object or array ends with its closing bracket.
  bool closed = false;

  final Object? _value;

  int get end => offset + length;

  /// What the node holds (`getNodeValue`): a property's key for its key
  /// node, a map or list for objects and arrays.
  Object? get value => switch (type) {
    JsoncNodeType.array => [for (final child in children) child.value],
    JsoncNodeType.object => {
      for (final property in children)
        if (property.children.length == 2)
          property.children[0]._value as String: property.children[1].value,
    },
    JsoncNodeType.property => null,
    _ => _value,
  };

  /// The node at [path] under this one (`findNodeAtLocation`): the last of
  /// duplicate keys, as reading them keeps; null when there is none.
  JsoncNode? find(List<Object> path) {
    JsoncNode? node = this;
    for (final segment in path) {
      if (node == null) return null;
      if (segment is String) {
        if (node.type != JsoncNodeType.object) return null;
        node = node._property(segment)?.children[1];
      } else if (segment is int) {
        if (node.type != JsoncNodeType.array ||
            segment < 0 ||
            segment >= node.children.length) {
          return null;
        }
        node = node.children[segment];
      } else {
        return null;
      }
    }
    return node;
  }

  /// This object's property [key] that has a value.
  JsoncNode? _property(String key) => children.lastWhereOrNull(
    (property) =>
        property.children.length == 2 && property.children[0]._value == key,
  );
}

extension<T> on List<T> {
  T? lastWhereOrNull(bool Function(T) test) {
    for (var i = length - 1; i >= 0; i--) {
      if (test(this[i])) return this[i];
    }
    return null;
  }
}

// --- Scanner --------------------------------------------------------------

enum _Token {
  openBrace,
  closeBrace,
  openBracket,
  closeBracket,
  comma,
  colon,
  nullKeyword,
  trueKeyword,
  falseKeyword,
  string,
  number,
  lineComment,
  blockComment,
  lineBreak,
  trivia,
  unknown,
  eof,
}

enum _ScanError {
  none,
  unexpectedEndOfComment,
  unexpectedEndOfString,
  unexpectedEndOfNumber,
  invalidUnicode,
  invalidEscapeCharacter,
  invalidCharacter,
}

const _tab = 0x09;
const _lf = 0x0A;
const _cr = 0x0D;
const _space = 0x20;
const _doubleQuote = 0x22;
const _asterisk = 0x2A;
const _comma = 0x2C;
const _minus = 0x2D;
const _slash = 0x2F;
const _zero = 0x30;
const _nine = 0x39;
const _colon = 0x3A;
const _openBracket = 0x5B;
const _backslash = 0x5C;
const _closeBracket = 0x5D;
const _openBrace = 0x7B;
const _closeBrace = 0x7D;
const _byteOrderMark = 0xFEFF;

bool _isWhiteSpace(int char) =>
    char == _space || char == _tab || char == _byteOrderMark;

bool _isLineBreak(int char) => char == _lf || char == _cr;

bool _isDigit(int char) => char >= _zero && char <= _nine;

/// `createScanner`: the tokens of [text], one [scan] at a time.
class _Scanner {
  _Scanner(this.text, {this.ignoreTrivia = false});

  final String text;
  final bool ignoreTrivia;
  int _pos = 0;
  String value = '';
  int tokenOffset = 0;
  _Token token = _Token.unknown;
  _ScanError error = _ScanError.none;

  int get tokenLength => _pos - tokenOffset;
  int get tokenEnd => _pos;

  /// The code unit at [index]; -1 past the end.
  int _at(int index) => index < text.length ? text.codeUnitAt(index) : -1;

  void setPosition(int position) {
    _pos = position;
    value = '';
    tokenOffset = 0;
    token = _Token.unknown;
    error = _ScanError.none;
  }

  _Token scan() {
    if (!ignoreTrivia) return _scanNext();
    _Token result;
    do {
      result = _scanNext();
    } while (result.index >= _Token.lineComment.index &&
        result.index <= _Token.trivia.index);
    return result;
  }

  int _scanHexDigits(int count) {
    var digits = 0;
    var result = 0;
    while (digits < count) {
      final char = _at(_pos);
      if (char >= _zero && char <= _nine) {
        result = result * 16 + char - _zero;
      } else if (char >= 0x41 && char <= 0x46) {
        result = result * 16 + char - 0x41 + 10;
      } else if (char >= 0x61 && char <= 0x66) {
        result = result * 16 + char - 0x61 + 10;
      } else {
        break;
      }
      _pos++;
      digits++;
    }
    return digits < count ? -1 : result;
  }

  String _scanNumber() {
    final start = _pos;
    if (_at(_pos) == _zero) {
      _pos++;
    } else {
      _pos++;
      while (_pos < text.length && _isDigit(_at(_pos))) {
        _pos++;
      }
    }
    if (_pos < text.length && _at(_pos) == 0x2E) {
      _pos++;
      if (_pos < text.length && _isDigit(_at(_pos))) {
        _pos++;
        while (_pos < text.length && _isDigit(_at(_pos))) {
          _pos++;
        }
      } else {
        error = _ScanError.unexpectedEndOfNumber;
        return text.substring(start, _pos);
      }
    }
    var end = _pos;
    if (_pos < text.length && (_at(_pos) == 0x45 || _at(_pos) == 0x65)) {
      _pos++;
      if (_pos < text.length && (_at(_pos) == 0x2B || _at(_pos) == _minus)) {
        _pos++;
      }
      if (_pos < text.length && _isDigit(_at(_pos))) {
        _pos++;
        while (_pos < text.length && _isDigit(_at(_pos))) {
          _pos++;
        }
        end = _pos;
      } else {
        error = _ScanError.unexpectedEndOfNumber;
      }
    }
    return text.substring(start, end);
  }

  String _scanString() {
    final result = StringBuffer();
    var start = _pos;
    while (true) {
      if (_pos >= text.length) {
        result.write(text.substring(start, _pos));
        error = _ScanError.unexpectedEndOfString;
        break;
      }
      final char = text.codeUnitAt(_pos);
      if (char == _doubleQuote) {
        result.write(text.substring(start, _pos));
        _pos++;
        break;
      }
      if (char == _backslash) {
        result.write(text.substring(start, _pos));
        _pos++;
        if (_pos >= text.length) {
          error = _ScanError.unexpectedEndOfString;
          break;
        }
        final escaped = text.codeUnitAt(_pos++);
        switch (escaped) {
          case _doubleQuote:
            result.write('"');
          case _backslash:
            result.write(r'\');
          case _slash:
            result.write('/');
          case 0x62: // b
            result.write('\b');
          case 0x66: // f
            result.write('\f');
          case 0x6E: // n
            result.write('\n');
          case 0x72: // r
            result.write('\r');
          case 0x74: // t
            result.write('\t');
          case 0x75: // u
            final code = _scanHexDigits(4);
            if (code >= 0) {
              result.writeCharCode(code);
            } else {
              error = _ScanError.invalidUnicode;
            }
          default:
            error = _ScanError.invalidEscapeCharacter;
        }
        start = _pos;
        continue;
      }
      if (char >= 0 && char <= 0x1F) {
        if (_isLineBreak(char)) {
          result.write(text.substring(start, _pos));
          error = _ScanError.unexpectedEndOfString;
          break;
        }
        // Marked, and read on.
        error = _ScanError.invalidCharacter;
      }
      _pos++;
    }
    return result.toString();
  }

  _Token _scanNext() {
    value = '';
    error = _ScanError.none;
    tokenOffset = _pos;
    if (_pos >= text.length) {
      tokenOffset = text.length;
      return token = _Token.eof;
    }
    var code = text.codeUnitAt(_pos);
    if (_isWhiteSpace(code)) {
      do {
        _pos++;
        code = _at(_pos);
      } while (_isWhiteSpace(code));
      value = text.substring(tokenOffset, _pos);
      return token = _Token.trivia;
    }
    if (_isLineBreak(code)) {
      _pos++;
      if (code == _cr && _at(_pos) == _lf) _pos++;
      value = text.substring(tokenOffset, _pos);
      return token = _Token.lineBreak;
    }
    switch (code) {
      case _openBrace:
        _pos++;
        return token = _Token.openBrace;
      case _closeBrace:
        _pos++;
        return token = _Token.closeBrace;
      case _openBracket:
        _pos++;
        return token = _Token.openBracket;
      case _closeBracket:
        _pos++;
        return token = _Token.closeBracket;
      case _colon:
        _pos++;
        return token = _Token.colon;
      case _comma:
        _pos++;
        return token = _Token.comma;
      case _doubleQuote:
        _pos++;
        value = _scanString();
        return token = _Token.string;
      case _slash:
        final start = _pos;
        if (_at(_pos + 1) == _slash) {
          _pos += 2;
          while (_pos < text.length && !_isLineBreak(_at(_pos))) {
            _pos++;
          }
          value = text.substring(start, _pos);
          return token = _Token.lineComment;
        }
        if (_at(_pos + 1) == _asterisk) {
          _pos += 2;
          final safeLength = text.length - 1; // For the lookahead.
          var closed = false;
          while (_pos < safeLength) {
            if (_at(_pos) == _asterisk && _at(_pos + 1) == _slash) {
              _pos += 2;
              closed = true;
              break;
            }
            _pos++;
          }
          if (!closed) {
            _pos = text.length;
            error = _ScanError.unexpectedEndOfComment;
          }
          value = text.substring(start, _pos);
          return token = _Token.blockComment;
        }
        _pos++;
        value = '/';
        return token = _Token.unknown;
      case _minus:
        _pos++;
        if (_pos == text.length || !_isDigit(_at(_pos))) {
          value = '-';
          return token = _Token.unknown;
        }
        value = '-${_scanNumber()}';
        return token = _Token.number;
    }
    if (_isDigit(code)) {
      value = _scanNumber();
      return token = _Token.number;
    }
    // A literal, or unknown: the whole word.
    while (_pos < text.length && _isUnknownContentCharacter(code)) {
      _pos++;
      code = _at(_pos);
    }
    if (tokenOffset != _pos) {
      value = text.substring(tokenOffset, _pos);
      return token = switch (value) {
        'true' => _Token.trueKeyword,
        'false' => _Token.falseKeyword,
        'null' => _Token.nullKeyword,
        _ => _Token.unknown,
      };
    }
    value = String.fromCharCode(code);
    _pos++;
    return token = _Token.unknown;
  }

  static bool _isUnknownContentCharacter(int code) {
    if (_isWhiteSpace(code) || _isLineBreak(code)) return false;
    return switch (code) {
      _closeBrace ||
      _closeBracket ||
      _openBrace ||
      _openBracket ||
      _doubleQuote ||
      _colon ||
      _comma ||
      _slash => false,
      _ => true,
    };
  }
}

// --- Parser ---------------------------------------------------------------

/// `visit` with `parseTree`'s visitor: comments and trailing commas
/// allowed, empty content too.
class _Parser {
  _Parser(String text, this._errors) : _scanner = _Scanner(text);

  final _Scanner _scanner;
  final List<JsoncParseError>? _errors;

  /// The artificial root the value is added to.
  final JsoncNode _root = JsoncNode._(JsoncNodeType.array, -1);
  late JsoncNode _parent = _root;

  JsoncNode? parse() {
    _scanNext();
    if (_scanner.token == _Token.eof) return null;
    if (!_parseValue()) {
      _handleError(JsoncErrorCode.valueExpected);
      return null;
    }
    if (_scanner.token != _Token.eof) {
      _handleError(JsoncErrorCode.endOfFileExpected);
    }
    final result = _root.children.firstOrNull;
    result?.parent = null;
    return result;
  }

  // The visitor.

  void _add(JsoncNode node) => _parent.children.add(node);

  void _ensurePropertyComplete(int endOffset) {
    if (_parent.type == JsoncNodeType.property) {
      _parent.length = endOffset - _parent.offset;
      _parent = _parent.parent!;
    }
  }

  void _onContainerBegin(JsoncNodeType type) {
    final node = JsoncNode._(type, _scanner.tokenOffset, parent: _parent);
    _add(node);
    _parent = node;
  }

  void _onContainerEnd({required _Token closing}) {
    final end = _scanner.tokenOffset + _scanner.tokenLength;
    // A property missing its value is complete here.
    _ensurePropertyComplete(end);
    _parent
      ..length = end - _parent.offset
      ..closed = _scanner.token == closing;
    _parent = _parent.parent!;
    _ensurePropertyComplete(end);
  }

  void _onObjectProperty(String name) {
    final property = JsoncNode._(
      JsoncNodeType.property,
      _scanner.tokenOffset,
      parent: _parent,
    );
    _add(property);
    _parent = property;
    property.children.add(
      JsoncNode._(
        JsoncNodeType.string,
        _scanner.tokenOffset,
        parent: property,
        length: _scanner.tokenLength,
        value: name,
      ),
    );
  }

  void _onLiteralValue(Object? value) {
    _add(
      JsoncNode._(
        switch (value) {
          String() => JsoncNodeType.string,
          num() => JsoncNodeType.number,
          bool() => JsoncNodeType.boolean,
          _ => JsoncNodeType.null_,
        },
        _scanner.tokenOffset,
        parent: _parent,
        length: _scanner.tokenLength,
        value: value,
      ),
    );
    _ensurePropertyComplete(_scanner.tokenOffset + _scanner.tokenLength);
  }

  void _onSeparator(int separator) {
    if (_parent.type != JsoncNodeType.property) return;
    if (separator == _colon) {
      _parent.colonOffset = _scanner.tokenOffset;
    } else {
      _ensurePropertyComplete(_scanner.tokenOffset);
    }
  }

  void _onError(JsoncErrorCode code) => _errors?.add(
    JsoncParseError(code, _scanner.tokenOffset, _scanner.tokenLength),
  );

  // The parser.

  _Token _scanNext() {
    while (true) {
      final token = _scanner.scan();
      switch (_scanner.error) {
        case _ScanError.invalidUnicode:
          _handleError(JsoncErrorCode.invalidUnicode);
        case _ScanError.invalidEscapeCharacter:
          _handleError(JsoncErrorCode.invalidEscapeCharacter);
        case _ScanError.unexpectedEndOfNumber:
          _handleError(JsoncErrorCode.unexpectedEndOfNumber);
        case _ScanError.unexpectedEndOfComment:
          _handleError(JsoncErrorCode.unexpectedEndOfComment);
        case _ScanError.unexpectedEndOfString:
          _handleError(JsoncErrorCode.unexpectedEndOfString);
        case _ScanError.invalidCharacter:
          _handleError(JsoncErrorCode.invalidCharacter);
        case _ScanError.none:
          break;
      }
      switch (token) {
        case _Token.lineComment ||
            _Token.blockComment ||
            _Token.trivia ||
            _Token.lineBreak:
          break;
        case _Token.unknown:
          _handleError(JsoncErrorCode.invalidSymbol);
        default:
          return token;
      }
    }
  }

  void _handleError(
    JsoncErrorCode code, {
    List<_Token> skipUntilAfter = const [],
    List<_Token> skipUntil = const [],
  }) {
    _onError(code);
    if (skipUntilAfter.isEmpty && skipUntil.isEmpty) return;
    var token = _scanner.token;
    while (token != _Token.eof) {
      if (skipUntilAfter.contains(token)) {
        _scanNext();
        break;
      } else if (skipUntil.contains(token)) {
        break;
      }
      token = _scanNext();
    }
  }

  bool _parseString({required bool isValue}) {
    final value = _scanner.value;
    if (isValue) {
      _onLiteralValue(value);
    } else {
      _onObjectProperty(value);
    }
    _scanNext();
    return true;
  }

  bool _parseLiteral() {
    switch (_scanner.token) {
      case _Token.number:
        final text = _scanner.value;
        num? value;
        if (!text.contains(RegExp('[.eE]'))) value = int.tryParse(text);
        value ??= double.tryParse(text);
        if (value == null) {
          _handleError(JsoncErrorCode.invalidNumberFormat);
          value = 0;
        }
        _onLiteralValue(value);
      case _Token.nullKeyword:
        _onLiteralValue(null);
      case _Token.trueKeyword:
        _onLiteralValue(true);
      case _Token.falseKeyword:
        _onLiteralValue(false);
      default:
        return false;
    }
    _scanNext();
    return true;
  }

  bool _parseProperty() {
    if (_scanner.token != _Token.string) {
      _handleError(
        JsoncErrorCode.propertyNameExpected,
        skipUntil: const [_Token.closeBrace, _Token.comma],
      );
      return false;
    }
    _parseString(isValue: false);
    if (_scanner.token == _Token.colon) {
      _onSeparator(_colon);
      _scanNext();
      if (!_parseValue()) {
        _handleError(
          JsoncErrorCode.valueExpected,
          skipUntil: const [_Token.closeBrace, _Token.comma],
        );
      }
    } else {
      _handleError(
        JsoncErrorCode.colonExpected,
        skipUntil: const [_Token.closeBrace, _Token.comma],
      );
    }
    return true;
  }

  bool _parseObject() {
    _onContainerBegin(JsoncNodeType.object);
    _scanNext();
    var needsComma = false;
    while (_scanner.token != _Token.closeBrace &&
        _scanner.token != _Token.eof) {
      if (_scanner.token == _Token.comma) {
        if (!needsComma) _handleError(JsoncErrorCode.valueExpected);
        _onSeparator(_comma);
        _scanNext();
        if (_scanner.token == _Token.closeBrace) break; // A trailing comma.
      } else if (needsComma) {
        _handleError(JsoncErrorCode.commaExpected);
      }
      if (!_parseProperty()) {
        _handleError(
          JsoncErrorCode.valueExpected,
          skipUntil: const [_Token.closeBrace, _Token.comma],
        );
      }
      needsComma = true;
    }
    _onContainerEnd(closing: _Token.closeBrace);
    if (_scanner.token != _Token.closeBrace) {
      _handleError(
        JsoncErrorCode.closeBraceExpected,
        skipUntilAfter: const [_Token.closeBrace],
      );
    } else {
      _scanNext();
    }
    return true;
  }

  bool _parseArray() {
    _onContainerBegin(JsoncNodeType.array);
    _scanNext();
    var needsComma = false;
    while (_scanner.token != _Token.closeBracket &&
        _scanner.token != _Token.eof) {
      if (_scanner.token == _Token.comma) {
        if (!needsComma) _handleError(JsoncErrorCode.valueExpected);
        _onSeparator(_comma);
        _scanNext();
        if (_scanner.token == _Token.closeBracket) break; // A trailing comma.
      } else if (needsComma) {
        _handleError(JsoncErrorCode.commaExpected);
      }
      if (!_parseValue()) {
        _handleError(
          JsoncErrorCode.valueExpected,
          skipUntil: const [_Token.closeBracket, _Token.comma],
        );
      }
      needsComma = true;
    }
    _onContainerEnd(closing: _Token.closeBracket);
    if (_scanner.token != _Token.closeBracket) {
      _handleError(
        JsoncErrorCode.closeBracketExpected,
        skipUntilAfter: const [_Token.closeBracket],
      );
    } else {
      _scanNext();
    }
    return true;
  }

  bool _parseValue() => switch (_scanner.token) {
    _Token.openBracket => _parseArray(),
    _Token.openBrace => _parseObject(),
    _Token.string => _parseString(isValue: true),
    _ => _parseLiteral(),
  };
}

// --- Formatting -----------------------------------------------------------

bool _isEOL(String text, int offset) =>
    offset >= 0 &&
    offset < text.length &&
    _isLineBreak(text.codeUnitAt(offset));

/// `getEOL`: the text's first line break, else [options]'.
String _eolOf(JsoncFormatting options, String text) {
  for (var i = 0; i < text.length; i++) {
    final char = text.codeUnitAt(i);
    if (char == _cr) {
      return i + 1 < text.length && text.codeUnitAt(i + 1) == _lf
          ? '\r\n'
          : '\r';
    }
    if (char == _lf) return '\n';
  }
  return options.eol;
}

/// `computeIndentLevel`: how deep [content]'s first line is indented.
int _indentLevel(String content, JsoncFormatting options) {
  var chars = 0;
  final tabSize = options.tabSize;
  for (var i = 0; i < content.length; i++) {
    final char = content.codeUnitAt(i);
    if (char == _space) {
      chars++;
    } else if (char == _tab) {
      chars += tabSize;
    } else {
      break;
    }
  }
  return chars ~/ tabSize;
}

String _indentUnit(JsoncFormatting options) =>
    options.insertSpaces ? ' ' * options.tabSize : '\t';

/// `format` (without `keepLines`) of the lines from [rangeStart] to
/// [rangeEnd]: the edits that lay what is there out, at the indentation the
/// first of those lines has.
List<JsoncEdit> _format(
  String documentText,
  int rangeStart,
  int rangeEnd,
  JsoncFormatting options,
) {
  var formatTextStart = rangeStart;
  while (formatTextStart > 0 && !_isEOL(documentText, formatTextStart - 1)) {
    formatTextStart--;
  }
  var endOffset = rangeEnd;
  while (endOffset < documentText.length && !_isEOL(documentText, endOffset)) {
    endOffset++;
  }
  final formatText = documentText.substring(formatTextStart, endOffset);
  final initialIndentLevel = _indentLevel(formatText, options);
  final eol = _eolOf(options, documentText);
  final indentValue = _indentUnit(options);
  var indentLevel = 0;
  var lineBreaks = false;
  var hasError = false;
  final scanner = _Scanner(formatText);

  String newLineAndIndent() =>
      eol + indentValue * math.max(0, initialIndentLevel + indentLevel);

  _Token scanNext() {
    var token = scanner.scan();
    lineBreaks = false;
    while (token == _Token.trivia || token == _Token.lineBreak) {
      if (token == _Token.lineBreak) lineBreaks = true;
      token = scanner.scan();
    }
    hasError = token == _Token.unknown || scanner.error != _ScanError.none;
    return token;
  }

  final edits = <JsoncEdit>[];
  void addEdit(String text, int startOffset, int endOffset) {
    if (!hasError &&
        startOffset < rangeEnd &&
        endOffset > rangeStart &&
        documentText.substring(startOffset, endOffset) != text) {
      edits.add(JsoncEdit(startOffset, endOffset - startOffset, text));
    }
  }

  var firstToken = scanNext();
  if (firstToken != _Token.eof) {
    final firstTokenStart = scanner.tokenOffset + formatTextStart;
    addEdit(indentValue * initialIndentLevel, formatTextStart, firstTokenStart);
  }
  while (firstToken != _Token.eof) {
    var firstTokenEnd = scanner.tokenEnd + formatTextStart;
    var secondToken = scanNext();
    var replaceContent = '';
    var needsLineBreak = false;
    while (!lineBreaks &&
        (secondToken == _Token.lineComment ||
            secondToken == _Token.blockComment)) {
      // A comment on the same line stays there, a space away.
      final commentTokenStart = scanner.tokenOffset + formatTextStart;
      addEdit(' ', firstTokenEnd, commentTokenStart);
      firstTokenEnd = scanner.tokenEnd + formatTextStart;
      needsLineBreak = secondToken == _Token.lineComment;
      replaceContent = needsLineBreak ? newLineAndIndent() : '';
      secondToken = scanNext();
    }
    if (secondToken == _Token.closeBrace) {
      if (firstToken != _Token.openBrace) {
        indentLevel--;
        replaceContent = newLineAndIndent();
      }
    } else if (secondToken == _Token.closeBracket) {
      if (firstToken != _Token.openBracket) {
        indentLevel--;
        replaceContent = newLineAndIndent();
      }
    } else {
      switch (firstToken) {
        case _Token.openBracket || _Token.openBrace:
          indentLevel++;
          replaceContent = newLineAndIndent();
        case _Token.comma || _Token.lineComment:
          replaceContent = newLineAndIndent();
        case _Token.blockComment:
          if (lineBreaks) {
            replaceContent = newLineAndIndent();
          } else if (!needsLineBreak) {
            replaceContent = ' ';
          }
        case _Token.colon:
          if (!needsLineBreak) replaceContent = ' ';
        case _Token.string:
          if (secondToken == _Token.colon && !needsLineBreak) {
            replaceContent = '';
          }
        case _Token.nullKeyword ||
            _Token.trueKeyword ||
            _Token.falseKeyword ||
            _Token.number ||
            _Token.closeBrace ||
            _Token.closeBracket:
          if ((secondToken == _Token.lineComment ||
                  secondToken == _Token.blockComment) &&
              !needsLineBreak) {
            replaceContent = ' ';
          } else if (secondToken != _Token.comma && secondToken != _Token.eof) {
            hasError = true;
          }
        case _Token.unknown:
          hasError = true;
        default:
          break;
      }
      if (lineBreaks &&
          (secondToken == _Token.lineComment ||
              secondToken == _Token.blockComment)) {
        replaceContent = newLineAndIndent();
      }
    }
    if (secondToken == _Token.eof) replaceContent = '';
    final secondTokenStart = scanner.tokenOffset + formatTextStart;
    addEdit(replaceContent, firstTokenEnd, secondTokenStart);
    firstToken = secondToken;
  }
  return edits;
}

// --- Modifying ------------------------------------------------------------

/// One [modifyJsonc]: the edits it makes to [text], and the part of the
/// result to lay out.
class _Modification {
  _Modification(this.text, this.options) : eol = _eolOf(options, text);

  final String text;
  final JsoncFormatting options;
  final String eol;
  final List<JsoncEdit> _edits = [];

  /// What to lay out, in the edited text.
  int? _formatStart;
  int? _formatEnd;

  /// Whether the lines around [_formatStart]..[_formatEnd] are laid out
  /// whole (what was inserted shares them with what was there).
  bool _formatLines = false;

  late final JsoncNode? root = parseJsoncTree(text);

  void plan(
    List<Object> path,
    Object? value, {
    required bool remove,
    required bool insert,
  }) {
    final segments = [...path];
    JsoncNode? parent;
    Object? last;
    while (segments.isNotEmpty) {
      last = segments.removeLast();
      parent = root?.find(segments);
      if (parent != null || remove) break;
      // Created on the way.
      value = last is String ? {last: value} : [value];
    }
    if (parent == null) {
      if (!remove) _setRoot(value);
      return;
    }
    if (parent.type == JsoncNodeType.object && last is String) {
      final property = parent._property(last);
      if (property != null) {
        if (remove) {
          _removeChild(parent, property);
        } else {
          _replace(property.children[1], value);
        }
      } else if (!remove) {
        _insertChild(
          parent,
          parent.children.length,
          '${jsonEncode(last)}: ${jsonEncode(value)}',
        );
      }
    } else if (parent.type == JsoncNodeType.array && last is int) {
      final length = parent.children.length;
      if (last < -1) {
        throw ArgumentError.value(path, 'path', 'negative index');
      }
      final exists = last >= 0 && last < length;
      if (remove) {
        if (exists) _removeChild(parent, parent.children[last]);
      } else if (insert || !exists) {
        _insertChild(
          parent,
          last == -1 ? length : math.min(last, length),
          jsonEncode(value),
        );
      } else {
        _replace(parent.children[last], value);
      }
    } else {
      throw FormatException(
        'Cannot ${remove ? 'remove' : 'set'} '
        '${last is String ? 'property ${jsonEncode(last)}' : 'index $last'} '
        'in ${parent.type == JsoncNodeType.null_ ? 'null' : 'a ${parent.type.name}'}',
        text,
        parent.offset,
      );
    }
  }

  List<JsoncEdit> result() {
    if (_edits.isEmpty) return const [];
    var edited = applyJsoncEdits(text, _edits);
    if (_formatStart case final start?) {
      var end = _formatEnd!;
      var begin = start;
      if (_formatLines) {
        while (begin > 0 && !_isEOL(edited, begin - 1)) {
          begin--;
        }
        while (end < edited.length && !_isEOL(edited, end)) {
          end++;
        }
      }
      edited = applyJsoncEdits(edited, _format(edited, begin, end, options));
    }
    // One edit, from the first change to the last.
    var prefix = 0;
    final shorter = math.min(text.length, edited.length);
    while (prefix < shorter &&
        text.codeUnitAt(prefix) == edited.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < shorter - prefix &&
        text.codeUnitAt(text.length - 1 - suffix) ==
            edited.codeUnitAt(edited.length - 1 - suffix)) {
      suffix++;
    }
    if (prefix == text.length && prefix == edited.length) return const [];
    return [
      JsoncEdit(
        prefix,
        text.length - suffix - prefix,
        edited.substring(prefix, edited.length - suffix),
      ),
    ];
  }

  // Setting.

  void _setRoot(Object? value) {
    final json = jsonEncode(value);
    final root = this.root;
    if (root != null) {
      _edits.add(JsoncEdit(root.offset, root.length, json));
      _formatAt(root.offset, json.length);
    } else if (text.trim().isEmpty) {
      _edits.add(JsoncEdit(0, text.length, json));
      _formatAt(0, json.length);
    } else {
      // Only comments: the value goes after them.
      final lineBreak = text.isNotEmpty && _isEOL(text, text.length - 1)
          ? ''
          : eol;
      _edits.add(JsoncEdit(text.length, 0, lineBreak + json));
      _formatAt(text.length + lineBreak.length, json.length);
    }
  }

  void _replace(JsoncNode node, Object? value) {
    final json = jsonEncode(value);
    _edits.add(JsoncEdit(node.offset, node.length, json));
    _formatAt(node.offset, json.length);
  }

  void _formatAt(int start, int length, {bool lines = false}) {
    _formatStart = start;
    _formatEnd = start + length;
    _formatLines = lines;
  }

  /// Inserts [content] (a value, or `"key": value`) into [parent] before
  /// its child [index], or after the last one.
  void _insertChild(JsoncNode parent, int index, String content) {
    final children = parent.children;
    if (index < children.length) {
      final child = children[index];
      final lineStart = _lineStart(child.offset);
      if (_blank(lineStart, child.offset)) {
        // A line of its own, indented as the child it goes before.
        final indent = text.substring(lineStart, child.offset);
        _edits.add(JsoncEdit(lineStart, 0, '$indent$content,$eol'));
        _formatAt(lineStart + indent.length, content.length);
      } else {
        _edits.add(JsoncEdit(child.offset, 0, '$content, '));
        _formatAt(child.offset, content.length);
      }
      return;
    }
    final last = children.lastOrNull;
    final closeOffset = parent.end - 1;
    final closeLineStart = parent.closed ? _lineStart(closeOffset) : -1;
    if (parent.closed &&
        closeLineStart > parent.offset &&
        _blank(closeLineStart, closeOffset)) {
      // The closing bracket has a line of its own: a new line above it.
      final trailingComma = last != null && _commaAfter(last) != null;
      if (last != null && !trailingComma) {
        _edits.add(JsoncEdit(last.end, 0, ','));
      }
      final lastLineStart = last == null ? -1 : _lineStart(last.offset);
      final indent = last != null && _blank(lastLineStart, last.offset)
          ? text.substring(lastLineStart, last.offset)
          : text.substring(closeLineStart, closeOffset) + _indentUnit(options);
      _edits.add(
        JsoncEdit(
          closeLineStart,
          0,
          '$indent$content${trailingComma ? ',' : ''}$eol',
        ),
      );
      final shift = last != null && !trailingComma ? 1 : 0;
      _formatAt(closeLineStart + shift + indent.length, content.length);
    } else if (last != null) {
      // After the last child, and its line laid out anew (`setProperty`).
      _edits.add(JsoncEdit(last.end, 0, ',$content'));
      _formatAt(last.end, content.length + 1, lines: true);
    } else {
      _edits.add(JsoncEdit(parent.offset + 1, 0, content));
      _formatAt(parent.offset + 1, content.length, lines: true);
    }
  }

  /// Removes [child] of [parent] (a property, or an array's value) with
  /// one comma, keeping the comments around it.
  void _removeChild(JsoncNode parent, JsoncNode child) {
    final children = parent.children;
    final index = children.indexOf(child);
    final comma = _commaAfter(child);
    final end = comma?.end ?? child.end;
    final lineStart = _lineStart(child.offset);
    final lineEnd = _triviaToLineEnd(end);
    final previousComma = index > 0 && comma == null
        ? _commaAfter(children[index - 1])
        : null;
    if (lineEnd != null && _blank(lineStart, child.offset)) {
      // Lines of its own (and a comment trailing it): gone whole.
      _edits.add(
        JsoncEdit(
          lineStart,
          lineEnd + _lineBreakLength(lineEnd) - lineStart,
          '',
        ),
      );
      if (previousComma != null) {
        _edits.add(JsoncEdit(previousComma.offset, 1, ''));
      }
      return;
    }
    if (children.length == 1 && parent.closed) {
      final inside =
          text.substring(parent.offset + 1, child.offset) +
          text.substring(end, parent.end - 1);
      if (inside.trim().isEmpty) {
        _edits.add(JsoncEdit(parent.offset + 1, parent.length - 2, ''));
        return;
      }
    }
    if (comma != null) {
      _edits.add(JsoncEdit(child.offset, _skipBlanks(end) - child.offset, ''));
    } else if (previousComma != null) {
      // The last one: the comma before it goes, and the blanks after that.
      final start = math.max(_blankStart(child.offset), previousComma.end);
      _edits
        ..add(JsoncEdit(previousComma.offset, 1, ''))
        ..add(JsoncEdit(start, child.end - start, ''));
    } else {
      _edits.add(JsoncEdit(child.offset, child.length, ''));
    }
  }

  // Looking around.

  /// The comma right after [node], past blanks and comments.
  ({int offset, int end})? _commaAfter(JsoncNode node) {
    final scanner = _Scanner(text, ignoreTrivia: true)..setPosition(node.end);
    return scanner.scan() == _Token.comma
        ? (offset: scanner.tokenOffset, end: scanner.tokenEnd)
        : null;
  }

  int _lineStart(int offset) {
    while (offset > 0 && !_isEOL(text, offset - 1)) {
      offset--;
    }
    return offset;
  }

  /// Whether only spaces and tabs are between [start] and [end].
  bool _blank(int start, int end) {
    for (var i = start; i < end; i++) {
      if (!_isWhiteSpace(text.codeUnitAt(i))) return false;
    }
    return true;
  }

  /// Past the spaces and tabs at [offset].
  int _skipBlanks(int offset) {
    while (offset < text.length && _isWhiteSpace(text.codeUnitAt(offset))) {
      offset++;
    }
    return offset;
  }

  /// Back over the spaces and tabs before [offset].
  int _blankStart(int offset) {
    while (offset > 0 && _isWhiteSpace(text.codeUnitAt(offset - 1))) {
      offset--;
    }
    return offset;
  }

  int _lineBreakLength(int offset) {
    if (!_isEOL(text, offset)) return 0;
    return text.startsWith('\r\n', offset) ? 2 : 1;
  }

  /// Where the line [from] is on ends (its line break, or the end of the
  /// text), when only blanks and comments follow on it; null otherwise.
  int? _triviaToLineEnd(int from) {
    var i = from;
    while (i < text.length) {
      final char = text.codeUnitAt(i);
      if (_isWhiteSpace(char)) {
        i++;
      } else if (_isLineBreak(char)) {
        return i;
      } else if (text.startsWith('//', i)) {
        while (i < text.length && !_isEOL(text, i)) {
          i++;
        }
        return i;
      } else if (text.startsWith('/*', i)) {
        final close = text.indexOf('*/', i + 2);
        if (close < 0) return null;
        if (text.substring(i, close).contains(RegExp('[\r\n]'))) return null;
        i = close + 2;
      } else {
        return null;
      }
    }
    return i;
  }
}
