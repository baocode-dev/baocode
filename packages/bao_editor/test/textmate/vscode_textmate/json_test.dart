// Adapted from vscode-textmate 9.3.2 (25b68dad…): src/tests/json.test.ts
// (MIT, see fixtures/LICENSE.md).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/textmate/vscode_textmate/json.dart';

void isValid(String json) {
  final expected = jsonDecode(json);
  final actual = parseJSON(json, null, false);
  expect(actual, equals(expected));
}

void isInvalid(String json) {
  var hadErr = false;
  try {
    parseJSON(json, null, false);
  } catch (err) {
    hadErr = true;
  }
  expect(hadErr, isTrue, reason: 'expected invalid: $json');
}

void main() {
  test('JSON Invalid body', () {
    isInvalid('{}[]');
    isInvalid('*');
  });

  test('JSON Trailing Whitespace', () {
    isValid('{}\n\n');
  });

  test('JSON Objects', () {
    isValid('{}');
    isValid('{"key": "value"}');
    isValid(
      '{"key1": true, "key2": 3, "key3": [null], "key4": { "nested": {}}}',
    );
    isValid('{"constructor": true }');

    isInvalid('{');
    isInvalid('{3:3}');
    isInvalid("{'key': 3}");
    isInvalid('{"key" 3}');
    isInvalid('{"key":3 "key2": 4}');
    isInvalid('{"key":42, }');
    isInvalid('{"key:42');
  });

  test('JSON Arrays', () {
    isValid('[]');
    isValid('[1, 2]');
    isValid('[1, "string", false, {}, [null]]');

    isInvalid('[');
    isInvalid('[,]');
    isInvalid('[1 2]');
    isInvalid('[true false]');
    isInvalid('[1, ]');
    isInvalid('[[]');
    isInvalid('["something"');
    isInvalid('[magic]');
  });

  test('JSON Strings', () {
    isValid(r'["string"]');
    isValid(r'["\"\\\/\b\f\n\r\t\u1234\u12AB"]');
    isValid(r'["\\"]');

    isInvalid('["');
    isInvalid('["]');
    isInvalid(r'["\z"]');
    isInvalid(r'["\u"]');
    isInvalid(r'["\u123"]');
    isInvalid(r'["\u123Z"]');
    isInvalid("['string']");
  });

  test('Numbers', () {
    isValid('[0, -1, 186.1, 0.123, -1.583e+4, 1.583E-4, 5e8]');

    // isInvalid('[+1]');
    // isInvalid('[01]');
    // isInvalid('[1.]');
    // isInvalid('[1.1+3]');
    // isInvalid('[1.4e]');
    // isInvalid('[-A]');
  });

  test('JSON misc', () {
    isValid('{}');
    isValid('[null]');
    isValid('{"a":true}');
    isValid('{\n\t"key" : {\n\t"key2": 42\n\t}\n}');
    isValid('{"key":[{"key2":42}]}');
    isValid('{\n\t\n}');
    isValid('{\n"first":true\n\n}');
    isValid('{\n"key":32,\n\n"key2":45}');
    isValid('{"a": 1,\n\n"d": 2}');
    isValid('{"a": 1, "a": 2}');
    isValid('{"a": { "a": 2, "a": 3}}');
    isValid('[{ "a": 2, "a": 3}]');
    isValid('{"key1":"first string", "key2":["second string"]}');

    isInvalid('{\n"key":32,\nerror\n}');
  });
}
