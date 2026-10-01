// Adapted from vscode-textmate 9.3.2 (25b68dad…): src/tests/matcher.test.ts
// (MIT, see fixtures/LICENSE.md).

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/textmate/vscode_textmate/matcher.dart';

typedef _MatcherTest = ({String expression, List<String> input, bool result});

const List<_MatcherTest> _tests = [
  (expression: 'foo', input: ['foo'], result: true),
  (expression: 'foo', input: ['bar'], result: false),
  (expression: '- foo', input: ['foo'], result: false),
  (expression: '- foo', input: ['bar'], result: true),
  (expression: '- - foo', input: ['bar'], result: false),
  (expression: 'bar foo', input: ['foo'], result: false),
  (expression: 'bar foo', input: ['bar'], result: false),
  (expression: 'bar foo', input: ['bar', 'foo'], result: true),
  (expression: 'bar - foo', input: ['bar'], result: true),
  (expression: 'bar - foo', input: ['foo', 'bar'], result: false),
  (expression: 'bar - foo', input: ['foo'], result: false),
  (expression: 'bar, foo', input: ['foo'], result: true),
  (expression: 'bar, foo', input: ['bar'], result: true),
  (expression: 'bar, foo', input: ['bar', 'foo'], result: true),
  (expression: 'bar, -foo', input: ['bar', 'foo'], result: true),
  (expression: 'bar, -foo', input: ['yo'], result: true),
  (expression: 'bar, -foo', input: ['foo'], result: false),
  (expression: '(foo)', input: ['foo'], result: true),
  (expression: '(foo - bar)', input: ['foo'], result: true),
  (expression: '(foo - bar)', input: ['foo', 'bar'], result: false),
  (expression: 'foo bar - (yo man)', input: ['foo', 'bar'], result: true),
  (expression: 'foo bar - (yo man)', input: ['foo', 'bar', 'yo'], result: true),
  (
    expression: 'foo bar - (yo man)',
    input: ['foo', 'bar', 'yo', 'man'],
    result: false,
  ),
  (
    expression: 'foo bar - (yo | man)',
    input: ['foo', 'bar', 'yo', 'man'],
    result: false,
  ),
  (
    expression: 'foo bar - (yo | man)',
    input: ['foo', 'bar', 'yo'],
    result: false,
  ),
  (
    expression: 'R:text.html - (comment.block, text.html source)',
    input: ['text.html', 'bar', 'source'],
    result: false,
  ),
  (
    expression: 'text.html.php - (meta.embedded | meta.tag), L:text.html.php meta.tag, L:source.js.embedded.html',
    input: ['text.html.php', 'bar', 'source.js'],
    result: true,
  ),
];

bool _nameMatcher(List<String> identifers, List<String> stackElements) {
  var lastIndex = 0;
  return identifers.every((identifier) {
    for (var i = lastIndex; i < stackElements.length; i++) {
      if (stackElements[i] == identifier) {
        lastIndex = i + 1;
        return true;
      }
    }
    return false;
  });
}

void main() {
  for (var index = 0; index < _tests.length; index++) {
    final tst = _tests[index];
    test('Matcher Test #$index', () {
      final matchers = createMatchers<List<String>>(
        tst.expression,
        _nameMatcher,
      );
      final result = matchers.any((m) => m.matcher(tst.input));
      expect(result, tst.result);
    });
  }
}
