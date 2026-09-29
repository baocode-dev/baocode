// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See lib/ide/editor/monaco/LICENSE.txt.
// Source-derived tests for pinned VS Code monarchCommon.ts (6a598d4a).

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/monaco/vs/editor/standalone/common/monarch/monarch_common.dart';
import 'package:monad/ide/editor/monaco/vs/editor/standalone/common/monarch/monarch_compile.dart'
    as compiler;

void main() {
  group('Monarch common', () {
    test('bracket values and fuzzy-action predicates match upstream', () {
      expect(MonarchBracket.none.value, 0);
      expect(MonarchBracket.open.value, 1);
      expect(MonarchBracket.close.value, -1);
      expect(isFuzzyActionArr(['a', const IAction(token: 'b')]), isTrue);
      expect(isFuzzyAction('a'), isTrue);
      expect(isFuzzyAction(const IAction(token: 'a')), isTrue);
      expect(isFuzzyAction(<FuzzyAction>[]), isFalse);
      expect(isString('a'), isTrue);
      expect(isIAction(const IAction()), isTrue);
      expect(isIAction('a'), isFalse);
    });

    test('empty, case folding and CSS token sanitization', () {
      final lexer = ILexerMin(languageId: 'test');
      expect(empty(null), isTrue);
      expect(empty(''), isTrue);
      expect(empty(' '), isFalse);
      expect(fixCase(lexer, 'AbÉ'), 'AbÉ');
      lexer.ignoreCase = true;
      expect(fixCase(lexer, 'AbÉ'), 'abé');
      expect(fixCase(lexer, ''), '');
      expect(sanitize('a&<>\'"_b.c:d-/'), 'a------b.c:d-/');
    });

    test('substitutes dollars, IDs, captures, attributes and state parts', () {
      final lexer = ILexerMin(
        languageId: 'sample',
        attributes: {'suffix': 'MiXeD', 'notString': 42},
      );
      expect(
        substituteMatches(
          lexer,
          r'$$|$#|$0|$1|$2|$01|$S0|$s1|$S2|$S3|$@suffix|$@languageId',
          'IDENT',
          ['ALL', 'FIRST', 'SECOND'],
          'Root.Child.Tail',
        ),
        r'$|IDENT|ALL|FIRST|SECOND|FIRST|Root.Child.Tail|Root|Child|Tail|MiXeD|sample',
      );
      lexer.ignoreCase = true;
      expect(
        substituteMatches(lexer, r'$#|$1|$S0|$S2|$@suffix', 'IDENT', [
          'ALL',
          'FIRST',
        ], 'Root.Child'),
        'ident|first|root.child|child|MiXeD',
      );
    });

    test('missing substitutions vanish and unmatched captures stringify', () {
      final lexer = ILexerMin(languageId: 'sample');
      expect(
        substituteMatches(
          lexer,
          r'$1|$2|$3|$99|$S9|$@missing|$unknown|@literal|$100',
          'id',
          ['all', null, ''],
          'root',
        ),
        r'undefined||||||$unknown|@literal|0',
      );
    });

    test(
      'regexp state substitution quotes the exact upstream character set',
      () {
        final lexer = ILexerMin(languageId: 'test', ignoreCase: true);
        expect(
          substituteMatchesRe(
            lexer,
            r'^$S2$|$s1|$S0|$S99',
            r'ROOT.A[\]{}*+?|^$()-',
          ),
          r'^a\[\\\]\{\}\*\+\?\|\^\$\(\)-$|root|root\.a\[\\\]\{\}\*\+\?\|\^\$\(\)-|',
        );
        expect(
          substituteMatchesRe(lexer, r'$1|$#|$$|$@attr', 'root'),
          r'$1|$#|$$|$@attr',
        );
        expect(substituteMatchesRe(lexer, r'$S2', 'root.😀'), '😀');
      },
    );

    test('findRules walks dotted parents and respects empty state rules', () {
      final lexer = compiler.compile('test', {
        'tokenizer': {
          'root': [
            ['x', 'root'],
          ],
          'root.child': <Object?>[],
        },
      });
      expect(
        findRules(lexer, 'root.extra.deep'),
        same(lexer.tokenizer['root']),
      );
      expect(
        findRules(lexer, 'root.child.deep'),
        same(lexer.tokenizer['root.child']),
      );
      expect(findRules(lexer, 'root.'), same(lexer.tokenizer['root']));
      expect(findRules(lexer, 'missing'), isNull);
      expect(findRules(lexer, ''), isNull);
    });

    test(
      'stateExists uses JavaScript truthiness and dotted parent fallback',
      () {
        final lexer = ILexerMin(
          languageId: 'test',
          stateNames: {
            'root': <Object?>[],
            'object': <String, Object?>{},
            'false': false,
            'zero': 0,
            'nan': double.nan,
            'empty': '',
            'null': null,
          },
        );
        expect(stateExists(lexer, 'root'), isTrue);
        expect(stateExists(lexer, 'root.child'), isTrue);
        expect(stateExists(lexer, 'object'), isTrue);
        for (final state in [
          'false',
          'zero',
          'nan',
          'empty',
          'null',
          'missing',
          '',
        ]) {
          expect(stateExists(lexer, state), isFalse, reason: state);
        }
      },
    );

    test('built-in attributes resolve like upstream object fields', () {
      final lexer = ILexer(languageId: 'test', tokenPostfix: '.suffix');
      expect(lexer['languageId'], 'test');
      expect(lexer['tokenPostfix'], '.suffix');
      expect(lexer['start'], isNull);
      expect(lexer.hasAttribute('start'), isTrue);
      expect(lexer.hasAttribute('missing'), isFalse);
      lexer.ignoreCase = true;
      expect(lexer['ignoreCase'], isTrue);
      expect(
        substituteMatches(lexer, r'$@tokenPostfix', '', [], ''),
        '.suffix',
      );
    });

    test('error text includes language id', () {
      final error = createError(ILexerMin(languageId: 'test'), 'bad state');
      expect(error, isA<MonarchError>());
      expect(error.message, 'test: bad state');
      expect(error.toString(), 'test: bad state');
    });

    test('logging includes language id', () {
      expect(
        () => log(ILexerMin(languageId: 'test'), 'message'),
        prints('test: message\n'),
      );
    });
  });
}
