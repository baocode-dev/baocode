// Checks jsToLowerCase against JavaScript's String.prototype.toLowerCase for
// every code point, as recorded from Node by
// tool/generate_language_detection_fixtures.mjs in
// test/fixtures/textmate/language_detection_lowercase.json.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/editor/monaco/vs/base/common/ecmascript_lower_case.dart';

void main() {
  test('matches JavaScript for every code point', () {
    final fixture = jsonDecode(
      File('test/fixtures/textmate/language_detection_lowercase.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
    final expected = <int, String>{
      for (final entry in fixture['mappings']! as List<Object?>)
        (entry! as List<Object?>)[0] as int: String.fromCharCodes(
          ((entry as List<Object?>)[1]! as List<Object?>).cast<int>(),
        ),
    };
    expect(expected, hasLength(greaterThan(1400)));
    final differences = <String>[];
    for (var c = 0; c <= 0x10FFFF; c++) {
      if (c >= 0xD800 && c <= 0xDFFF) continue;
      final s = String.fromCharCode(c);
      final want = expected[c] ?? s;
      if (jsToLowerCase(s) != want) differences.add(c.toRadixString(16));
    }
    expect(differences, isEmpty);
  });

  test('strings', () {
    expect(jsToLowerCase('Foo.JSON'), 'foo.json');
    const ascii = 'already/lower.ts';
    expect(identical(jsToLowerCase(ascii), ascii), isTrue);
    expect(jsToLowerCase('FOO.İNİ'), 'foo.i̇ni̇');
    expect(jsToLowerCase('\u{10400}X'), '\u{10428}x'); // Deseret
    expect(jsToLowerCase('A\uD800B'), 'a\uD800b'); // lone surrogate kept
  });

  test('deviation: no Final_Sigma context', () {
    // JavaScript gives 'ας' (final sigma); the port always uses σ.
    expect(jsToLowerCase('ΑΣ'), 'ασ');
    expect(jsToLowerCase('Σ'), 'σ'); // same as JavaScript
  });
}
