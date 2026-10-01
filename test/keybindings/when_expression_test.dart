import 'package:flutter_test/flutter_test.dart';
import 'package:monad/keybindings/when_expression.dart';

void main() {
  Object? Function(String) context(Map<String, Object?> values) =>
      (key) => values[key];

  bool holds(String text, Map<String, Object?> values) =>
      WhenExpression.parse(text).evaluate(context(values));

  test('a key holds when it is truthy', () {
    expect(holds('editorTextFocus', {'editorTextFocus': true}), isTrue);
    expect(holds('editorTextFocus', {}), isFalse);
    expect(holds('editorLangId', {'editorLangId': ''}), isFalse);
    expect(holds('count', {'count': 0}), isFalse);
    expect(holds('count', {'count': 2}), isTrue);
  });

  test('!, && and || with parentheses, && binding tighter', () {
    final values = {'a': true, 'b': false, 'c': true};
    expect(holds('a && !b', values), isTrue);
    expect(holds('b || c', values), isTrue);
    expect(holds('b && a || c', values), isTrue);
    expect(holds('b && (a || c)', values), isFalse);
    expect(holds('!(a && c)', values), isFalse);
    expect(holds('!!a', values), isTrue);
  });

  test('== and != compare with a value, quoted or not', () {
    final values = {'lang': 'dart', 'n': 3};
    expect(holds("lang == 'dart'", values), isTrue);
    expect(holds('lang == dart', values), isTrue);
    expect(holds("lang != 'dart'", values), isFalse);
    expect(holds('n == 3', values), isTrue);
    expect(holds("missing != 'x'", values), isTrue);
    // As upstream: `key == true` is `key`.
    expect(holds('a == true', {'a': true}), isTrue);
    expect(holds('a != true', {'a': true}), isFalse);
  });

  test('an empty clause holds', () {
    expect(holds('', {}), isTrue);
    expect(holds('true', {}), isTrue);
    expect(holds('false', {}), isFalse);
  });

  test('reports the keys it reads', () {
    expect(WhenExpression.parse("a && (b || c != 'x') && !d").keys, {
      'a',
      'b',
      'c',
      'd',
    });
  });

  test('what it does not support does not parse, and never holds', () {
    for (final text in [
      'a =~ /x/',
      "a in 'list'",
      'a not in b',
      'a < 3',
      'a &&',
      '(a',
      "a == 'x",
    ]) {
      final expression = WhenExpression.parse(text);
      expect(expression.error, isNotNull, reason: text);
      expect(expression.evaluate((_) => true), isFalse, reason: text);
      expect(expression.serialize(), text);
    }
  });

  test('serializes as upstream writes it', () {
    expect(
      WhenExpression.parse("a&&!b||c=='x'").serialize(),
      "a && !b || c == 'x'",
    );
    expect(WhenExpression.parse('a && (b || c)').serialize(), 'a && (b || c)');
    expect(WhenExpression.parse('!(a && b)').serialize(), '!(a && b)');
    expect(
      WhenExpression.parse('a && b'),
      WhenExpression.parse('a&&b'),
      reason: 'equal when they serialize the same',
    );
  });
}
