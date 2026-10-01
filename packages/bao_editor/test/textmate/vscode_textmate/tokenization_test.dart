// Adapted from vscode-textmate 9.3.2 (25b68dad…):
// src/tests/tokenization.test.ts (MIT, see fixtures/LICENSE.md).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/editor/textmate/vscode_textmate/js_semantics.dart';
import 'package:baocode/ide/editor/textmate/vscode_textmate/main.dart';

import 'support/fixtures.dart';
import 'support/onig.dart';

void assertTokenizationSuite(String testLocation) {
  final tests = jsonDecode(readFixture(testLocation)) as List;
  final testDir = fixturePath(
    testLocation.substring(0, testLocation.lastIndexOf('/')),
  );

  for (final tst in tests.cast<Map<String, Object?>>()) {
    final desc = tst['desc']! as String;
    test(desc, () async {
      await performTest(tst, testDir, testOnigLib());
    });
  }
}

Future<void> performTest(
  Map<String, Object?> test,
  String testDir,
  Future<IOnigLib> onigLib,
) async {
  var grammarScopeName = test['grammarScopeName'] as String?;
  final grammarByScope = <String, IRawGrammar>{};
  for (final grammarPath in (test['grammars']! as List).cast<String>()) {
    final content = File('$testDir/$grammarPath').readAsStringSync();
    final rawGrammar = parseRawGrammar(content, grammarPath);
    grammarByScope[rawGrammar.scopeName] = rawGrammar;
    if (grammarScopeName == null && grammarPath == test['grammarPath']) {
      grammarScopeName = rawGrammar.scopeName;
    }
  }
  if (grammarScopeName == null) {
    throw StateError('I HAVE NO GRAMMAR FOR TEST');
  }

  final grammarInjections = (test['grammarInjections'] as List?)
      ?.cast<String>();
  final options = RegistryOptions(
    onigLib: onigLib,
    loadGrammar: (scopeName) async => grammarByScope[scopeName],
    getInjections: (scopeName) {
      if (scopeName == grammarScopeName) {
        return grammarInjections;
      }
      return null;
    },
  );
  final registry = Registry(options);
  final grammar = await registry.loadGrammar(grammarScopeName);
  if (grammar == null) {
    throw StateError('I HAVE NO GRAMMAR FOR TEST');
  }
  StateStack? prevState;
  for (final line in (test['lines']! as List).cast<Map<String, Object?>>()) {
    prevState = assertLineTokenization(grammar, line, prevState);
  }
}

StateStack assertLineTokenization(
  IGrammar grammar,
  Map<String, Object?> testCase,
  StateStack? prevState,
) {
  final line = testCase['line']! as String;
  final actual = grammar.tokenizeLine(line, prevState);

  final actualTokens = [
    for (final token in actual.tokens)
      {
        'value': jsSubstring(line, token.startIndex, token.endIndex),
        'scopes': token.scopes,
      },
  ];

  // TODO@Alex: fix tests instead of working around
  var expectedTokens = (testCase['tokens']! as List)
      .cast<Map<String, Object?>>();
  if (line.isNotEmpty) {
    // Remove empty tokens...
    expectedTokens = expectedTokens
        .where((token) => (token['value']! as String).isNotEmpty)
        .toList();
  }

  expect(actualTokens, expectedTokens, reason: 'Tokenizing line $line');

  var ruleStack = actual.ruleStack;
  if (prevState != null) {
    final diff = diffStateStacksRefEq(prevState, actual.ruleStack);
    ruleStack = applyStateStackDiff(prevState, diff)!;
  }

  return ruleStack;
}

void main() {
  group('first-mate', () {
    assertTokenizationSuite('first-mate/tests.json');
  });
  group('suite1', () {
    assertTokenizationSuite('suite1/tests.json');
  });
  group('suite1 while', () {
    assertTokenizationSuite('suite1/whileTests.json');
  });
}
