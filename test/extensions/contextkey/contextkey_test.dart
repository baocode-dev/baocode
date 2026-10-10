/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/platform/contextkey/test/common/contextkey.test.ts (every case),
// plus checks of the JavaScript value semantics this port reproduces.

import 'package:baocode/extensions/contextkey/contextkey.dart';
import 'package:baocode/extensions/contextkey/js_values.dart';
import 'package:flutter_test/flutter_test.dart';

ContextKeyLookup createContext(Map<String, Object?> ctx) =>
    (key) => ctx[key];

void main() {
  group('ContextKeyExpr', () {
    test('ContextKeyExpr.equals', () {
      final a = ContextKeyExpr.and([
        ContextKeyExpr.has('a1'),
        ContextKeyExpr.and([ContextKeyExpr.has('and.a')]),
        ContextKeyExpr.has('a2'),
        ContextKeyExpr.regex('d3', JsRegExp('d.*')),
        ContextKeyExpr.regex('d4', JsRegExp(r'\*\*3*')),
        ContextKeyExpr.equals('b1', 'bb1'),
        ContextKeyExpr.equals('b2', 'bb2'),
        ContextKeyExpr.notEquals('c1', 'cc1'),
        ContextKeyExpr.notEquals('c2', 'cc2'),
        ContextKeyExpr.not('d1'),
        ContextKeyExpr.not('d2'),
      ])!;
      final b = ContextKeyExpr.and([
        ContextKeyExpr.equals('b2', 'bb2'),
        ContextKeyExpr.notEquals('c1', 'cc1'),
        ContextKeyExpr.not('d1'),
        ContextKeyExpr.regex('d4', JsRegExp(r'\*\*3*')),
        ContextKeyExpr.notEquals('c2', 'cc2'),
        ContextKeyExpr.has('a2'),
        ContextKeyExpr.equals('b1', 'bb1'),
        ContextKeyExpr.regex('d3', JsRegExp('d.*')),
        ContextKeyExpr.has('a1'),
        ContextKeyExpr.and([ContextKeyExpr.equals('and.a', true)]),
        ContextKeyExpr.not('d2'),
      ])!;
      expect(a.equals(b), isTrue);
    });

    test('issue #134942: Equals in comparator expressions', () {
      void testEquals(ContextKeyExpression expr, String str) {
        final deserialized = ContextKeyExpr.deserialize(str);
        expect(deserialized, isNotNull);
        expect(expr.equals(deserialized!), isTrue, reason: str);
      }

      testEquals(ContextKeyExpr.greater('value', 0), 'value > 0');
      testEquals(ContextKeyExpr.greaterEquals('value', 0), 'value >= 0');
      testEquals(ContextKeyExpr.smaller('value', 0), 'value < 0');
      testEquals(ContextKeyExpr.smallerEquals('value', 0), 'value <= 0');
    });

    test('normalize', () {
      final key1IsTrue = ContextKeyExpr.equals('key1', true);
      final key1IsNotFalse = ContextKeyExpr.notEquals('key1', false);
      final key1IsFalse = ContextKeyExpr.equals('key1', false);
      final key1IsNotTrue = ContextKeyExpr.notEquals('key1', true);
      expect(key1IsTrue.equals(ContextKeyExpr.has('key1')), isTrue);
      expect(key1IsNotFalse.equals(ContextKeyExpr.has('key1')), isTrue);
      expect(key1IsFalse.equals(ContextKeyExpr.not('key1')), isTrue);
      expect(key1IsNotTrue.equals(ContextKeyExpr.not('key1')), isTrue);
    });

    test('evaluate', () {
      final context = createContext({
        'a': true,
        'b': false,
        'c': '5',
        'd': 'd',
      });
      void testExpression(String expr, bool expected) {
        final rules = ContextKeyExpr.deserialize(expr);
        expect(rules!.evaluate(context), expected, reason: expr);
      }

      void testBatch(String expr, Object? value) {
        testExpression(expr, jsTruthy(value));
        testExpression('$expr == true', jsTruthy(value));
        testExpression('$expr != true', !jsTruthy(value));
        testExpression('$expr == false', !jsTruthy(value));
        testExpression('$expr != false', jsTruthy(value));
        testExpression('$expr == 5', jsLooseEquals(value, '5'));
        testExpression('$expr != 5', !jsLooseEquals(value, '5'));
        testExpression('!$expr', !jsTruthy(value));
        testExpression(
          '$expr =~ /d.*/',
          RegExp('d.*').hasMatch(jsToString(value)),
        );
        testExpression(
          '$expr =~ /D/i',
          RegExp('D', caseSensitive: false).hasMatch(jsToString(value)),
        );
      }

      testBatch('a', true);
      testBatch('b', false);
      testBatch('c', '5');
      testBatch('d', 'd');
      testBatch('z', null);

      testExpression('true', true);
      testExpression('false', false);
      testExpression('a && !b', true);
      testExpression('a && b', false);
      testExpression('a && !b && c == 5', true);
      testExpression('d =~ /e.*/', false);
      testExpression('b && a || a', true);
      testExpression('a || b', true);
      testExpression('b || b', false);
      testExpression('b && a || a && b', false);
    });

    test('negate', () {
      void testNegate(String expr, String expected) {
        final actual = ContextKeyExpr.deserialize(expr)!.negate().serialize();
        expect(actual, expected);
      }

      testNegate('true', 'false');
      testNegate('false', 'true');
      testNegate('a', '!a');
      testNegate('a && b || c', '!a && !c || !b && !c');
      testNegate('a && b || c || d', '!a && !c && !d || !b && !c && !d');
      testNegate(
        '!a && !b || !c && !d',
        'a && c || a && d || b && c || b && d',
      );
      testNegate(
        '!a && !b || !c && !d || !e && !f',
        'a && c && e || a && c && f || a && d && e || a && d && f || '
            'b && c && e || b && c && f || b && d && e || b && d && f',
      );
    });

    test('false, true', () {
      void testNormalize(String expr, String expected) {
        expect(ContextKeyExpr.deserialize(expr)!.serialize(), expected);
      }

      final constants = contextKeyConstants;
      testNormalize('true', 'true');
      testNormalize('!true', 'false');
      testNormalize('false', 'false');
      testNormalize('!false', 'true');
      testNormalize('a && true', 'a');
      testNormalize('a && false', 'false');
      testNormalize('a || true', 'true');
      testNormalize('a || false', 'a');
      testNormalize('isMac', '${constants['isMac']}');
      testNormalize('isLinux', '${constants['isLinux']}');
      testNormalize('isWindows', '${constants['isWindows']}');
    });

    test('issue #101015: distribute OR', () {
      void t(String expr1, String expr2, String? expected) {
        final e1 = ContextKeyExpr.deserialize(expr1);
        final e2 = ContextKeyExpr.deserialize(expr2);
        expect(ContextKeyExpr.and([e1, e2])?.serialize(), expected);
      }

      t('a', 'b', 'a && b');
      t('a || b', 'c', 'a && c || b && c');
      t('a || b', 'c || d', 'a && c || a && d || b && c || b && d');
      t('a || b', 'c && d', 'a && c && d || b && c && d');
      t(
        'a || b',
        'c && d || e',
        'a && e || b && e || a && c && d || b && c && d',
      );
    });

    test('ContextKeyInExpr', () {
      final ainb = ContextKeyExpr.deserialize('a in b')!;
      bool e(Map<String, Object?> ctx) => ainb.evaluate(createContext(ctx));
      expect(
        e({
          'a': 3,
          'b': [3, 2, 1],
        }),
        isTrue,
      );
      expect(
        e({
          'a': 3,
          'b': [1, 2, 3],
        }),
        isTrue,
      );
      expect(
        e({
          'a': 3,
          'b': [1, 2],
        }),
        isFalse,
      );
      expect(e({'a': 3}), isFalse);
      expect(e({'a': 3, 'b': null}), isFalse);
      expect(
        e({
          'a': 'x',
          'b': ['x'],
        }),
        isTrue,
      );
      expect(
        e({
          'a': 'x',
          'b': ['y'],
        }),
        isFalse,
      );
      expect(e({'a': 'x', 'b': <String, Object?>{}}), isFalse);
      expect(
        e({
          'a': 'x',
          'b': {'x': false},
        }),
        isTrue,
      );
      expect(
        e({
          'a': 'x',
          'b': {'x': true},
        }),
        isTrue,
      );
      expect(e({'a': 'prototype', 'b': <String, Object?>{}}), isFalse);
    });

    test('ContextKeyNotInExpr', () {
      final aNotInB = ContextKeyExpr.deserialize('a not in b')!;
      bool e(Map<String, Object?> ctx) => aNotInB.evaluate(createContext(ctx));
      expect(
        e({
          'a': 3,
          'b': [3, 2, 1],
        }),
        isFalse,
      );
      expect(
        e({
          'a': 3,
          'b': [1, 2, 3],
        }),
        isFalse,
      );
      expect(
        e({
          'a': 3,
          'b': [1, 2],
        }),
        isTrue,
      );
      expect(e({'a': 3}), isTrue);
      expect(e({'a': 3, 'b': null}), isTrue);
      expect(
        e({
          'a': 'x',
          'b': ['x'],
        }),
        isFalse,
      );
      expect(
        e({
          'a': 'x',
          'b': ['y'],
        }),
        isTrue,
      );
      expect(e({'a': 'x', 'b': <String, Object?>{}}), isTrue);
      expect(
        e({
          'a': 'x',
          'b': {'x': false},
        }),
        isFalse,
      );
      expect(
        e({
          'a': 'x',
          'b': {'x': true},
        }),
        isFalse,
      );
      expect(e({'a': 'prototype', 'b': <String, Object?>{}}), isTrue);
    });

    test('issue #106524: distributing AND should normalize', () {
      final actual = ContextKeyExpr.and([
        ContextKeyExpr.or([ContextKeyExpr.has('a'), ContextKeyExpr.has('b')]),
        ContextKeyExpr.has('c'),
      ]);
      final expected = ContextKeyExpr.or([
        ContextKeyExpr.and([ContextKeyExpr.has('a'), ContextKeyExpr.has('c')]),
        ContextKeyExpr.and([ContextKeyExpr.has('b'), ContextKeyExpr.has('c')]),
      ]);
      expect(actual!.equals(expected!), isTrue);
    });

    test('issue #129625: Removes duplicated terms in OR expressions', () {
      final expr = ContextKeyExpr.or([
        ContextKeyExpr.has('A'),
        ContextKeyExpr.has('B'),
        ContextKeyExpr.has('A'),
      ])!;
      expect(expr.serialize(), 'A || B');
    });

    test('Resolves true constant OR expressions', () {
      final expr = ContextKeyExpr.or([
        ContextKeyExpr.has('A'),
        ContextKeyExpr.not('A'),
      ])!;
      expect(expr.serialize(), 'true');
    });

    test('Resolves false constant AND expressions', () {
      final expr = ContextKeyExpr.and([
        ContextKeyExpr.has('A'),
        ContextKeyExpr.not('A'),
      ])!;
      expect(expr.serialize(), 'false');
    });

    test('issue #129625: Removes duplicated terms in AND expressions', () {
      final expr = ContextKeyExpr.and([
        ContextKeyExpr.has('A'),
        ContextKeyExpr.has('B'),
        ContextKeyExpr.has('A'),
      ])!;
      expect(expr.serialize(), 'A && B');
    });

    test('issue #129625: Remove duplicated terms when negating', () {
      final expr = ContextKeyExpr.and([
        ContextKeyExpr.has('A'),
        ContextKeyExpr.or([ContextKeyExpr.has('B1'), ContextKeyExpr.has('B2')]),
      ])!;
      expect(expr.serialize(), 'A && B1 || A && B2');
      expect(
        expr.negate().serialize(),
        '!A || !A && !B1 || !A && !B2 || !B1 && !B2',
      );
      expect(expr.negate().negate().serialize(), 'A && B1 || A && B2');
      expect(
        expr.negate().negate().negate().serialize(),
        '!A || !A && !B1 || !A && !B2 || !B1 && !B2',
      );
    });

    bool strImplies(String p0, String q0) => implies(
      ContextKeyExpr.deserialize(p0)!,
      ContextKeyExpr.deserialize(q0)!,
    );

    test('issue #129625: remove redundant terms in OR expressions', () {
      expect(strImplies('a && b', 'a'), isTrue);
      expect(strImplies('a', 'a && b'), isFalse);
    });

    test('implies', () {
      expect(strImplies('a', 'a'), isTrue);
      expect(strImplies('a', 'a || b'), isTrue);
      expect(strImplies('a', 'a && b'), isFalse);
      expect(strImplies('a', 'a && b || a && c'), isFalse);
      expect(strImplies('a && b', 'a'), isTrue);
      expect(strImplies('a && b', 'b'), isTrue);
      expect(strImplies('a && b', 'a && b || c'), isTrue);
      expect(strImplies('a || b', 'a || c'), isFalse);
      expect(strImplies('a || b', 'a || b'), isTrue);
      expect(strImplies('a && b', 'a && b'), isTrue);
      expect(strImplies('a || b', 'a || b || c'), isTrue);
      expect(strImplies('c && a && b', 'c && a'), isTrue);
    });

    test('Greater, GreaterEquals, Smaller, SmallerEquals evaluate', () {
      void checkEvaluate(String expr, Map<String, Object?> ctx, bool expected) {
        final e = ContextKeyExpr.deserialize(expr)!;
        expect(e.evaluate(createContext(ctx)), expected, reason: '$expr $ctx');
      }

      checkEvaluate('a > 1', {}, false);
      checkEvaluate('a > 1', {'a': 0}, false);
      checkEvaluate('a > 1', {'a': 1}, false);
      checkEvaluate('a > 1', {'a': 2}, true);
      checkEvaluate('a > 1', {'a': '0'}, false);
      checkEvaluate('a > 1', {'a': '1'}, false);
      checkEvaluate('a > 1', {'a': '2'}, true);
      checkEvaluate('a > 1', {'a': 'a'}, false);

      checkEvaluate('a > 10', {'a': 2}, false);
      checkEvaluate('a > 10', {'a': 11}, true);
      checkEvaluate('a > 10', {'a': '11'}, true);
      checkEvaluate('a > 10', {'a': '2'}, false);
      checkEvaluate('a > 10', {'a': '11'}, true);

      checkEvaluate('a > 1.1', {'a': 1}, false);
      checkEvaluate('a > 1.1', {'a': 2}, true);
      checkEvaluate('a > 1.1', {'a': 11}, true);
      checkEvaluate('a > 1.1', {'a': '1.1'}, false);
      checkEvaluate('a > 1.1', {'a': '2'}, true);
      checkEvaluate('a > 1.1', {'a': '11'}, true);

      checkEvaluate('a > b', {'a': 'b'}, false);
      checkEvaluate('a > b', {'a': 'c'}, false);
      checkEvaluate('a > b', {'a': 1000}, false);

      checkEvaluate('a >= 2', {'a': '1'}, false);
      checkEvaluate('a >= 2', {'a': '2'}, true);
      checkEvaluate('a >= 2', {'a': '3'}, true);

      checkEvaluate('a < 2', {'a': '1'}, true);
      checkEvaluate('a < 2', {'a': '2'}, false);
      checkEvaluate('a < 2', {'a': '3'}, false);

      checkEvaluate('a <= 2', {'a': '1'}, true);
      checkEvaluate('a <= 2', {'a': '2'}, true);
      checkEvaluate('a <= 2', {'a': '3'}, false);
    });

    test('Greater, GreaterEquals, Smaller, SmallerEquals negate', () {
      void checkNegate(String expr, String expected) {
        final a = ContextKeyExpr.deserialize(expr)!;
        expect(a.negate().serialize(), expected);
      }

      checkNegate('a > 1', 'a <= 1');
      checkNegate('a > 1.1', 'a <= 1.1');
      checkNegate('a > b', 'a <= b');
      checkNegate('a >= 1', 'a < 1');
      checkNegate('a >= 1.1', 'a < 1.1');
      checkNegate('a >= b', 'a < b');
      checkNegate('a < 1', 'a >= 1');
      checkNegate('a < 1.1', 'a >= 1.1');
      checkNegate('a < b', 'a >= b');
      checkNegate('a <= 1', 'a > 1');
      checkNegate('a <= 1.1', 'a > 1.1');
      checkNegate('a <= b', 'a > b');
    });

    test('issue #111899: context keys can use `<` or `>` ', () {
      final actual = ContextKeyExpr.deserialize(
        'editorTextFocus && vim.active && vim.use<C-r>',
      )!;
      expect(
        actual.equals(
          ContextKeyExpr.and([
            ContextKeyExpr.has('editorTextFocus'),
            ContextKeyExpr.has('vim.active'),
            ContextKeyExpr.has('vim.use<C-r>'),
          ])!,
        ),
        isTrue,
      );
    });
  });

  group('JavaScript semantics', () {
    test('loose equality as `==`', () {
      expect(jsLooseEquals(5, '5'), isTrue);
      expect(jsLooseEquals(true, '1'), isTrue);
      expect(jsLooseEquals(false, ''), isTrue);
      expect(jsLooseEquals(null, ''), isFalse);
      expect(jsLooseEquals(['a', 'b'], 'a,b'), isTrue);
    });

    test('regex tests String(value), undefined included', () {
      final e = ContextKeyExpr.deserialize('z =~ /def/')!;
      expect(e.evaluate(createContext({})), isTrue); // 'undefined'
      expect(
        ContextKeyExpr.deserialize('n =~ /^42\$/')!
            .evaluate(createContext({'n': 42})),
        isTrue,
      );
    });

    test('quoted regex, the old syntax (lenient parser only)', () {
      expect(
        ContextKeyExpr.deserialize("viewItem =~ '/^(Starting|Started)/'"),
        isNull,
      );
      final e = ContextKeyExpr.deserializeLenient(
        "viewItem =~ '/^(Starting|Started)/'",
      )!;
      expect(e.evaluate(createContext({'viewItem': 'Started'})), isTrue);
      expect(e.evaluate(createContext({'viewItem': 'Stopped'})), isFalse);
    });

    test('validateWhenClauses', () {
      final errors = validateWhenClauses(['a && b', 'a &&', "foo == 'x"]);
      expect(errors[0], isEmpty);
      expect(errors[1], isNotEmpty);
      expect(errors[2].single.offset, 7);
    });
  });
}
