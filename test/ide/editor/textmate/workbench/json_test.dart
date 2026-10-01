// The scanner and parse tests are ported from VS Code
// src/vs/base/test/common/json.test.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971 (MIT); the tree tests are not, as
// `parseTree` is not ported. The last group covers error collection.

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/editor/monaco/vs/base/common/json.dart';
import 'package:baocode/ide/editor/monaco/vs/base/common/json_error_messages.dart';

void assertKinds(String text, List<int> kinds) {
  final scanner = createScanner(text);
  final remaining = [...kinds];
  int kind;
  while ((kind = scanner.scan()) != SyntaxKind.eof) {
    expect(remaining, isNotEmpty, reason: 'unexpected token $kind in $text');
    expect(kind, remaining.removeAt(0), reason: text);
  }
  expect(remaining, isEmpty, reason: text);
}

void assertScanError(String text, int expectedKind, int scanError) {
  final scanner = createScanner(text);
  scanner.scan();
  expect(scanner.getToken(), expectedKind);
  expect(scanner.getTokenError(), scanError);
}

void assertValidParse(
  String input,
  Object? expected, [
  ParseOptions options = ParseOptions.DEFAULT,
]) {
  final errors = <ParseError>[];
  final actual = parse(input, errors, options);
  expect(
    errors,
    isEmpty,
    reason: errors.isEmpty ? null : getParseErrorMessage(errors[0].error),
  );
  expect(actual, equals(expected));
}

void assertInvalidParse(
  String input,
  Object? expected, [
  ParseOptions options = ParseOptions.DEFAULT,
]) {
  final errors = <ParseError>[];
  final actual = parse(input, errors, options);
  expect(errors, isNotEmpty);
  expect(actual, equals(expected));
}

void main() {
  test('tokens', () {
    assertKinds('{', [SyntaxKind.openBraceToken]);
    assertKinds('}', [SyntaxKind.closeBraceToken]);
    assertKinds('[', [SyntaxKind.openBracketToken]);
    assertKinds(']', [SyntaxKind.closeBracketToken]);
    assertKinds(':', [SyntaxKind.colonToken]);
    assertKinds(',', [SyntaxKind.commaToken]);
  });

  test('comments', () {
    assertKinds('// this is a comment', [SyntaxKind.lineCommentTrivia]);
    assertKinds('// this is a comment\n', [
      SyntaxKind.lineCommentTrivia,
      SyntaxKind.lineBreakTrivia,
    ]);
    assertKinds('/* this is a comment*/', [SyntaxKind.blockCommentTrivia]);
    assertKinds('/* this is a \r\ncomment*/', [SyntaxKind.blockCommentTrivia]);
    assertKinds('/* this is a \ncomment*/', [SyntaxKind.blockCommentTrivia]);

    // unexpected end
    assertKinds('/* this is a', [SyntaxKind.blockCommentTrivia]);
    assertKinds('/* this is a \ncomment', [SyntaxKind.blockCommentTrivia]);

    // broken comment
    assertKinds('/ ttt', [
      SyntaxKind.unknown,
      SyntaxKind.trivia,
      SyntaxKind.unknown,
    ]);
  });

  test('strings', () {
    assertKinds('"test"', [SyntaxKind.stringLiteral]);
    assertKinds('"\\""', [SyntaxKind.stringLiteral]);
    assertKinds('"\\/"', [SyntaxKind.stringLiteral]);
    assertKinds('"\\b"', [SyntaxKind.stringLiteral]);
    assertKinds('"\\f"', [SyntaxKind.stringLiteral]);
    assertKinds('"\\n"', [SyntaxKind.stringLiteral]);
    assertKinds('"\\r"', [SyntaxKind.stringLiteral]);
    assertKinds('"\\t"', [SyntaxKind.stringLiteral]);
    assertKinds('"\\v"', [SyntaxKind.stringLiteral]);
    assertKinds('"\u88ff"', [SyntaxKind.stringLiteral]);
    assertKinds('"\u200b\u2028"', [SyntaxKind.stringLiteral]);

    // unexpected end
    assertKinds('"test', [SyntaxKind.stringLiteral]);
    assertKinds('"test\n"', [
      SyntaxKind.stringLiteral,
      SyntaxKind.lineBreakTrivia,
      SyntaxKind.stringLiteral,
    ]);

    // invalid characters
    assertScanError(
      '"\t"',
      SyntaxKind.stringLiteral,
      ScanError.invalidCharacter,
    );
    assertScanError(
      '"\t "',
      SyntaxKind.stringLiteral,
      ScanError.invalidCharacter,
    );
  });

  test('numbers', () {
    assertKinds('0', [SyntaxKind.numericLiteral]);
    assertKinds('0.1', [SyntaxKind.numericLiteral]);
    assertKinds('-0.1', [SyntaxKind.numericLiteral]);
    assertKinds('-1', [SyntaxKind.numericLiteral]);
    assertKinds('1', [SyntaxKind.numericLiteral]);
    assertKinds('123456789', [SyntaxKind.numericLiteral]);
    assertKinds('10', [SyntaxKind.numericLiteral]);
    assertKinds('90', [SyntaxKind.numericLiteral]);
    assertKinds('90E+123', [SyntaxKind.numericLiteral]);
    assertKinds('90e+123', [SyntaxKind.numericLiteral]);
    assertKinds('90e-123', [SyntaxKind.numericLiteral]);
    assertKinds('90E-123', [SyntaxKind.numericLiteral]);
    assertKinds('90E123', [SyntaxKind.numericLiteral]);
    assertKinds('90e123', [SyntaxKind.numericLiteral]);

    // zero handling
    assertKinds('01', [SyntaxKind.numericLiteral, SyntaxKind.numericLiteral]);
    assertKinds('-01', [SyntaxKind.numericLiteral, SyntaxKind.numericLiteral]);

    // unexpected end
    assertKinds('-', [SyntaxKind.unknown]);
    assertKinds('.0', [SyntaxKind.unknown]);
  });

  test('keywords: true, false, null', () {
    assertKinds('true', [SyntaxKind.trueKeyword]);
    assertKinds('false', [SyntaxKind.falseKeyword]);
    assertKinds('null', [SyntaxKind.nullKeyword]);

    assertKinds('true false null', [
      SyntaxKind.trueKeyword,
      SyntaxKind.trivia,
      SyntaxKind.falseKeyword,
      SyntaxKind.trivia,
      SyntaxKind.nullKeyword,
    ]);

    // invalid words
    assertKinds('nulllll', [SyntaxKind.unknown]);
    assertKinds('True', [SyntaxKind.unknown]);
    assertKinds('foo-bar', [SyntaxKind.unknown]);
    assertKinds('foo bar', [
      SyntaxKind.unknown,
      SyntaxKind.trivia,
      SyntaxKind.unknown,
    ]);
  });

  test('trivia', () {
    assertKinds(' ', [SyntaxKind.trivia]);
    assertKinds('  \t  ', [SyntaxKind.trivia]);
    assertKinds('  \t  \n  \t  ', [
      SyntaxKind.trivia,
      SyntaxKind.lineBreakTrivia,
      SyntaxKind.trivia,
    ]);
    assertKinds('\r\n', [SyntaxKind.lineBreakTrivia]);
    assertKinds('\r', [SyntaxKind.lineBreakTrivia]);
    assertKinds('\n', [SyntaxKind.lineBreakTrivia]);
    assertKinds('\n\r', [
      SyntaxKind.lineBreakTrivia,
      SyntaxKind.lineBreakTrivia,
    ]);
    assertKinds('\n   \n', [
      SyntaxKind.lineBreakTrivia,
      SyntaxKind.trivia,
      SyntaxKind.lineBreakTrivia,
    ]);
  });

  test('parse: literals', () {
    assertValidParse('true', true);
    assertValidParse('false', false);
    assertValidParse('null', null);
    assertValidParse('"foo"', 'foo');
    assertValidParse(
      '"\\"-\\\\-\\/-\\b-\\f-\\n-\\r-\\t"',
      '"-\\-/-\b-\f-\n-\r-\t',
    );
    assertValidParse('"\\u00DC"', 'Ü');
    assertValidParse('9', 9);
    assertValidParse('-9', -9);
    assertValidParse('0.129', 0.129);
    assertValidParse('23e3', 23e3);
    assertValidParse('1.2E+3', 1.2E+3);
    assertValidParse('1.2E-3', 1.2E-3);
    assertValidParse('1.2E-3 // comment', 1.2E-3);
  });

  test('parse: objects', () {
    assertValidParse('{}', <String, Object?>{});
    assertValidParse('{ "foo": true }', {'foo': true});
    assertValidParse('{ "bar": 8, "xoo": "foo" }', {'bar': 8, 'xoo': 'foo'});
    assertValidParse('{ "hello": [], "world": {} }', {
      'hello': [],
      'world': <String, Object?>{},
    });
    assertValidParse('{ "a": false, "b": true, "c": [ 7.4 ] }', {
      'a': false,
      'b': true,
      'c': [7.4],
    });
    assertValidParse(
      '{ "lineComment": "//", "blockComment": ["/*", "*/"], "brackets": '
      '[ ["{", "}"], ["[", "]"], ["(", ")"] ] }',
      {
        'lineComment': '//',
        'blockComment': ['/*', '*/'],
        'brackets': [
          ['{', '}'],
          ['[', ']'],
          ['(', ')'],
        ],
      },
    );
    assertValidParse('{ "hello": [], "world": {} }', {
      'hello': [],
      'world': <String, Object?>{},
    });
    assertValidParse('{ "hello": { "again": { "inside": 5 }, "world": 1 }}', {
      'hello': {
        'again': {'inside': 5},
        'world': 1,
      },
    });
    assertValidParse('{ "foo": /*hello*/true }', {'foo': true});
  });

  test('parse: arrays', () {
    assertValidParse('[]', []);
    assertValidParse('[ [],  [ [] ]]', [
      [],
      [[]],
    ]);
    assertValidParse('[ 1, 2, 3 ]', [1, 2, 3]);
    assertValidParse('[ { "a": null } ]', [
      {'a': null},
    ]);
  });

  test('parse: objects with errors', () {
    assertInvalidParse('{,}', <String, Object?>{});
    assertInvalidParse('{ "foo": true, }', {
      'foo': true,
    }, const ParseOptions(allowTrailingComma: false));
    assertInvalidParse('{ "bar": 8 "xoo": "foo" }', {'bar': 8, 'xoo': 'foo'});
    assertInvalidParse('{ ,"bar": 8 }', {'bar': 8});
    assertInvalidParse('{ ,"bar": 8, "foo" }', {'bar': 8});
    assertInvalidParse('{ "bar": 8, "foo": }', {'bar': 8});
    assertInvalidParse('{ 8, "foo": 9 }', {'foo': 9});
  });

  test('parse: array with errors', () {
    assertInvalidParse('[,]', []);
    assertInvalidParse('[ 1, 2, ]', [
      1,
      2,
    ], const ParseOptions(allowTrailingComma: false));
    assertInvalidParse('[ 1 2, 3 ]', [1, 2, 3]);
    assertInvalidParse('[ ,1, 2, 3 ]', [1, 2, 3]);
    assertInvalidParse('[ ,1, 2, 3, ]', [
      1,
      2,
      3,
    ], const ParseOptions(allowTrailingComma: false));
  });

  test('parse: disallow commments', () {
    const options = ParseOptions(disallowComments: true);

    assertValidParse('[ 1, 2, null, "foo" ]', [1, 2, null, 'foo'], options);
    assertValidParse('{ "hello": [], "world": {} }', {
      'hello': [],
      'world': <String, Object?>{},
    }, options);

    assertInvalidParse('{ "foo": /*comment*/ true }', {'foo': true}, options);
  });

  test('parse: trailing comma', () {
    // default is allow
    assertValidParse('{ "hello": [], }', {'hello': []});

    var options = const ParseOptions(allowTrailingComma: true);
    assertValidParse('{ "hello": [], }', {'hello': []}, options);
    assertValidParse('{ "hello": [] }', {'hello': []}, options);
    assertValidParse('{ "hello": [], "world": {}, }', {
      'hello': [],
      'world': <String, Object?>{},
    }, options);
    assertValidParse('{ "hello": [], "world": {} }', {
      'hello': [],
      'world': <String, Object?>{},
    }, options);
    assertValidParse('{ "hello": [1,] }', {
      'hello': [1],
    }, options);

    options = const ParseOptions(allowTrailingComma: false);
    assertInvalidParse('{ "hello": [], }', {'hello': []}, options);
    assertInvalidParse('{ "hello": [], "world": {}, }', {
      'hello': [],
      'world': <String, Object?>{},
    }, options);
  });

  group('error collection', () {
    test('records codes, offsets and lengths as upstream', () {
      final errors = <ParseError>[];
      final value = parse('{ "a": 1 "b": [2,, 3], "c" }', errors);
      expect(value, {
        'a': 1,
        'b': [2, 3],
      });
      expect(errors, const [
        ParseError(error: ParseErrorCode.commaExpected, offset: 9, length: 3),
        ParseError(error: ParseErrorCode.valueExpected, offset: 17, length: 1),
        ParseError(error: ParseErrorCode.colonExpected, offset: 27, length: 1),
      ]);
      expect(errors.map((e) => getParseErrorMessage(e.error)), [
        'Comma expected',
        'Value expected',
        'Colon expected',
      ]);
    });

    test('reports scan errors and keeps parsing', () {
      final errors = <ParseError>[];
      expect(parse('["\\x", "\\u12", 1.]', errors), ['', '', 0]);
      expect(errors, const [
        ParseError(
          error: ParseErrorCode.invalidEscapeCharacter,
          offset: 1,
          length: 4,
        ),
        ParseError(error: ParseErrorCode.invalidUnicode, offset: 7, length: 6),
        ParseError(
          error: ParseErrorCode.unexpectedEndOfNumber,
          offset: 15,
          length: 2,
        ),
        ParseError(
          error: ParseErrorCode.invalidNumberFormat,
          offset: 15,
          length: 2,
        ),
      ]);
    });

    test('empty content and trailing content', () {
      final errors = <ParseError>[];
      expect(parse('', errors), isNull);
      expect(errors.single.error, ParseErrorCode.valueExpected);

      errors.clear();
      expect(
        parse('', errors, const ParseOptions(allowEmptyContent: true)),
        isNull,
      );
      expect(errors, isEmpty);

      // The unknown symbol is skipped, so the scanner then reaches the end.
      errors.clear();
      expect(parse('{} x', errors), <String, Object?>{});
      expect(errors, const [
        ParseError(error: ParseErrorCode.invalidSymbol, offset: 3, length: 1),
      ]);
    });

    test('a theme file with comments and trailing commas', () {
      final errors = <ParseError>[];
      final value = parse(
        '// header\n{\n\t"include": "./base.json", /* inline */\n'
        '\t"colors": { "editor.background": "#1e1e1e", },\n'
        '\t"tokenColors": [ { "scope": ["a", "b",], "settings": {} }, ],\n}\n',
        errors,
      );
      expect(errors, isEmpty);
      expect(value, {
        'include': './base.json',
        'colors': {'editor.background': '#1e1e1e'},
        'tokenColors': [
          {
            'scope': ['a', 'b'],
            'settings': <String, Object?>{},
          },
        ],
      });
      expect(getNodeType(value), 'object');
    });

    test('a comment at offset 0 keeps its text', () {
      final scanner = createScanner('/*x*/');
      expect(scanner.scan(), SyntaxKind.blockCommentTrivia);
      expect(scanner.getTokenValue(), '/*x*/');
      expect(scanner.getTokenOffset(), 0);
      expect(scanner.getTokenLength(), 5);
    });
  });

  test('getNodeType', () {
    expect(getNodeType(true), 'boolean');
    expect(getNodeType(1), 'number');
    expect(getNodeType(1.5), 'number');
    expect(getNodeType('x'), 'string');
    expect(getNodeType(null), 'null');
    expect(getNodeType(<Object?>[]), 'array');
    expect(getNodeType(<String, Object?>{}), 'object');
  });
}
