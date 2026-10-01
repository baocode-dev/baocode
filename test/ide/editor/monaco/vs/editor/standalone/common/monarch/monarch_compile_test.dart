// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See lib/ide/editor/monaco/LICENSE.txt.
// Source-derived compiler tests for VS Code 6a598d4a monarchCompile.ts.
// The embedded-case fixture also follows standalone/test/browser/monarch.test.ts.

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/editor/monaco/vs/editor/standalone/common/monarch/monarch_common.dart';
import 'package:baocode/ide/editor/monaco/vs/editor/standalone/common/monarch/monarch_compile.dart';
import 'package:baocode/ide/editor/monaco/vs/editor/standalone/common/monarch/monarch_types.dart';

ILexer _lexerForAction(
  Object? action, {
  Map<String, Object?> attributes = const {},
}) => compile('test', {
  ...attributes,
  'tokenizer': {
    'root': [
      [r'.+', action],
    ],
    'other': <Object?>[],
  },
});

IAction _action(Object? action, {Map<String, Object?> attributes = const {}}) =>
    _lexerForAction(action, attributes: attributes).tokenizer['root']![0].action
        as IAction;

FuzzyAction _case(
  Map<String, Object?> cases,
  String id, {
  List<String?>? matches,
  String state = 'root',
  bool eos = false,
  Map<String, Object?> attributes = const {},
}) => _action({'cases': cases}, attributes: attributes).test!(
  id,
  matches ?? [id],
  state,
  eos,
);

Matcher _errorContaining(String text) => isA<MonarchError>().having(
  (error) => error.message,
  'message',
  contains(text),
);

void main() {
  group('Monarch compiler defaults and state rules', () {
    test('defaults and first state are identical to upstream', () {
      final lexer = compile('sample', const {
        'tokenizer': {'first': <Object?>[], 'second': <Object?>[]},
      });
      expect(lexer.languageId, 'sample');
      expect(lexer.start, 'first');
      expect(lexer.maxStack, 100);
      expect(lexer.noThrow, isTrue);
      expect(lexer.ignoreCase, isFalse);
      expect(lexer.unicode, isFalse);
      expect(lexer.includeLF, isFalse);
      expect(lexer.usesEmbedded, isFalse);
      expect(lexer.defaultToken, 'source');
      expect(lexer.tokenPostfix, '.sample');
      // The compiler-only stateNames/raw attributes are not copied upstream.
      expect(lexer.stateNames, isEmpty);
      expect(lexer.attributes, isEmpty);
      expect(compile('empty', {'tokenizer': {}}).start, isNull);
    });

    test('explicit options retain types, empty tokens and postfixes', () {
      final lexer = compile('sample', {
        'start': 'second',
        'maxStack': 3, // Not read by the pinned compiler.
        'includeLF': true,
        'ignoreCase': true,
        'unicode': true,
        'defaultToken': '',
        'tokenPostfix': '',
        'tokenizer': {'first': [], 'second': []},
      });
      expect(lexer.start, 'second');
      expect(lexer.maxStack, 100);
      expect(lexer.includeLF, isTrue);
      expect(lexer.ignoreCase, isTrue);
      expect(lexer.unicode, isTrue);
      expect(lexer.defaultToken, '');
      expect(lexer.tokenPostfix, '');
      final fallback = compile('sample', {
        'start': false,
        'includeLF': 1,
        'ignoreCase': 'true',
        'unicode': 'true',
        'defaultToken': false,
        'tokenPostfix': null,
        'tokenizer': {'root': []},
      });
      expect(fallback.start, 'root');
      expect(fallback.includeLF, isFalse);
      expect(fallback.ignoreCase, isFalse);
      expect(fallback.unicode, isFalse);
      expect(fallback.defaultToken, 'source');
      expect(fallback.tokenPostfix, '.sample');
    });

    test(
      'states and cases retain JavaScript integer-key enumeration order',
      () {
        final lexer = compile('sample', {
          'tokenizer': {'root': [], '10': [], '2': [], '01': []},
        });
        expect(lexer.start, '2');
        expect(lexer.tokenizer.keys, ['2', '10', 'root', '01']);
        expect(_case({'@default': 'fallback', '2': 'two'}, '2'), 'two');
      },
    );

    test(
      'includes expand in order and carry their nested diagnostic names',
      () {
        final lexer = compile('sample', {
          'tokenizer': {
            'root': [
              ['a', 'first'],
              {'include': '@shared'},
              {'include': 'empty'},
              ['z', 'last'],
              {'include': 'shared'},
            ],
            'shared': [
              ['b', 'middle'],
              {'include': '@nested'},
            ],
            'nested': [
              ['c', 'nested'],
            ],
            'empty': [],
          },
        });
        expect(lexer.tokenizer['root']!.map((rule) => rule.action), [
          'first',
          'middle',
          'nested',
          'last',
          'middle',
          'nested',
        ]);
        expect(
          lexer.tokenizer['root']![2].name,
          'tokenizer.root.shared.nested: c',
        );
        expect(
          lexer.tokenizer['root']![1],
          isNot(same(lexer.tokenizer['shared']![0])),
        );
      },
    );

    test(
      'short and expanded rule forms preserve anchors and action defaults',
      () {
        final lexer = compile('sample', {
          'tokenizer': {
            'root': [
              ['^x', 'start'],
              ['y'],
              {
                'regex': RegExp('z'),
                'action': 'end',
                'name': 'named',
                'matchOnlyAtStart': true,
                'matchOnlyAtLineStart': true,
              },
            ],
          },
        });
        final rules = lexer.tokenizer['root']!;
        expect(rules[0].matchOnlyAtLineStart, isTrue);
        expect(rules[0].resolveRegex('root').pattern, '^(?:x)');
        expect((rules[1].action as IAction).token, '');
        expect(rules[2].name, 'named: z');
        // The source setRegex overwrites an expanded rule's start flag.
        expect(rules[2].matchOnlyAtLineStart, isFalse);
      },
    );

    test(
      'shorthand third field overrides next without mutating const input',
      () {
        const IMonarchLanguage language = {
          'tokenizer': {
            'root': [
              ['a', 'first', '@other'],
              [
                'b',
                {'token': 'second', 'next': '@missing'},
                '@root.child',
              ],
            ],
            'other': <Object?>[],
          },
        };
        final lexer = compile('sample', language);
        expect((lexer.tokenizer['root']![0].action as IAction).next, 'other');
        expect(
          (lexer.tokenizer['root']![1].action as IAction).next,
          'root.child',
        );
        expect(language.containsKey('languageId'), isFalse);
        expect(language.containsKey('brackets'), isFalse);
        final original =
            ((language['tokenizer'] as Map)['root'] as List)[1] as List;
        expect((original[1] as Map)['next'], '@missing');
        expect(compile('sample', language).start, 'root');
      },
    );

    test('malformed state containers, includes and rules are rejected', () {
      expect(
        () => compile('x', null),
        throwsA(_errorContaining('definition object')),
      );
      expect(
        () => compile('x', []),
        throwsA(_errorContaining('definition object')),
      );
      expect(() => compile('x', {}), throwsA(_errorContaining("'tokenizer'")));
      for (final rule in [
        {'include': 1},
        {'include': '@missing'},
        <Object?>[],
        ['a', 'a', 'a', 'a'],
        {'regex': ''},
        [12, 'token'],
        ['a', 12, '@root'],
      ]) {
        expect(
          () => compile('test', {
            'tokenizer': {
              'root': [rule],
            },
          }),
          throwsA(isA<MonarchError>()),
          reason: '$rule',
        );
      }
      expect(
        () => compile('test', {
          'tokenizer': {'root': 'bad'},
        }),
        throwsA(_errorContaining('rules must be an array')),
      );
      expect(
        () => compile('test', {
          'tokenizer': {
            'root': [
              {'include': '@other'},
            ],
            'other': [
              {'include': '@root'},
            ],
          },
        }),
        throwsA(_errorContaining('cyclic include')),
      );
    });
  });

  group('Monarch regexp compilation', () {
    ILexer regexpLexer(
      Object pattern, {
      Map<String, Object?> attributes = const {},
    }) => compile('test', {
      ...attributes,
      'tokenizer': {
        'root': [
          [pattern, 'token'],
        ],
      },
    });

    test('anchors patterns and discards input regexp flags', () {
      final rule = regexpLexer(
        RegExp('a.b', caseSensitive: false, multiLine: true, dotAll: true),
      ).tokenizer['root']!.single;
      final regex = rule.resolveRegex('root');
      expect(regex.pattern, '^(?:a.b)');
      expect(regex.hasMatch('axb'), isTrue);
      expect(regex.hasMatch('Axb'), isFalse);
      expect(regex.hasMatch('a\nb'), isFalse);
      expect(regex.hasMatch('xaxb'), isFalse);
      expect(regex.hasMatch('\naxb'), isFalse);
    });

    test(
      'language flags control regexp case folding and Unicode code points',
      () {
        final regex = regexpLexer(
          r'a\u{1F600}',
          attributes: {'ignoreCase': true, 'unicode': true},
        ).tokenizer['root']!.single.resolveRegex('root');
        expect(regex.hasMatch('A😀'), isTrue);
        expect(regex.firstMatch('A😀')!.end, 3); // UTF-16, not code points.
        expect(regex.isCaseSensitive, isFalse);
        expect(regex.isUnicode, isTrue);
        final dot = regexpLexer('.').tokenizer['root']!.single
            .resolveRegex('root');
        expect(dot.firstMatch('😀')!.end, 1);
      },
    );

    test(
      'expands string/regexp attributes, nested attributes and escaped @@',
      () {
        final regex = regexpLexer(
          r'@word:@@literal:@empty',
          attributes: {
            'word': r'@letters+',
            'letters': RegExp('[a-z]', caseSensitive: false),
            'empty': '',
          },
        ).tokenizer['root']!.single.resolveRegex('root');
        expect(regex.pattern, r'^(?:(?:(?:[a-z])+):@literal:)');
        expect(regex.hasMatch('abc:@literal:'), isTrue);
        expect(regex.hasMatch('ABC:@literal:'), isFalse);
        expect(
          regexpLexer(
            '@@@word',
            attributes: {'word': 'x'},
          ).tokenizer['root']!.single.resolveRegex('root').hasMatch('@x'),
          isTrue,
        );
      },
    );

    test('limits attribute expansion to five passes just like upstream', () {
      final regex = regexpLexer(
        '@a',
        attributes: {
          'a': '@b',
          'b': '@c',
          'c': '@d',
          'd': '@e',
          'e': '@f',
          'f': 'x',
        },
      ).tokenizer['root']!.single.resolveRegex('root');
      expect(regex.hasMatch('@f'), isTrue);
      expect(regex.hasMatch('x'), isFalse);
    });

    test(
      'state regexps substitute escaped state text and cache the last state',
      () {
        final rule = regexpLexer(r'^$S2$').tokenizer['root']!.single;
        final first = rule.resolveRegex(r'root.a+b[0]');
        expect(rule.matchOnlyAtLineStart, isTrue);
        expect(first.pattern, r'^(?:a\+b\[0\]$)');
        expect(first.hasMatch('a+b[0]'), isTrue);
        expect(first.hasMatch('aaab0'), isFalse);
        expect(rule.resolveRegex(r'root.a+b[0]'), same(first));
        final second = rule.resolveRegex('root.other');
        expect(second.hasMatch('other'), isTrue);
        expect(second.hasMatch('a+b[0]'), isFalse);
        expect(rule.resolveRegex('root.other'), same(second));
        expect(rule.resolveRegex('root').hasMatch(''), isTrue);
      },
    );

    test('attribute expansion can introduce dynamic state references', () {
      final rule = regexpLexer(
        '@state',
        attributes: {'state': r'$S2'},
      ).tokenizer['root']!.single;
      expect(rule.resolveRegex('root.a+b').hasMatch('a+b'), isTrue);
    });

    test('retains captures, lookarounds, backreferences and empty matches', () {
      final regex = regexpLexer(r'(a)(?=b)(b)\1(?<!c)')
          .tokenizer['root']!
          .single
          .resolveRegex('root');
      final match = regex.firstMatch('aba')!;
      expect(match.groupCount, 2);
      expect(match.groups([0, 1, 2]), ['aba', 'a', 'b']);
      expect(
        regexpLexer('').tokenizer['root']!.single
            .resolveRegex('root')
            .firstMatch('anything')!
            .end,
        0,
      );
    });

    test('RegExp.source normalization preserves slashes and line escapes', () {
      final lexer = regexpLexer(
        RegExp('/\n\r  '),
        attributes: {'attr': RegExp('')},
      );
      final rule = lexer.tokenizer['root']!.single;
      // JavaScript RegExp.source escapes both Unicode line separators.
      final escapedSeparators = String.fromCharCodes([
        92, 117, 50, 48, 50, 56, // backslash + u2028
        92, 117, 50, 48, 50, 57, // backslash + u2029
      ]);
      final source = r'\/\n\r' + escapedSeparators;
      expect(rule.name, 'tokenizer.root: $source');
      expect(rule.resolveRegex('root').pattern, '^(?:$source)');
      expect(rule.resolveRegex('root').hasMatch('/\n\r  '), isTrue);
      expect(
        regexpLexer(
          '@attr',
          attributes: {'attr': RegExp('')},
        ).tokenizer['root']!.single.resolveRegex('root').pattern,
        r'^(?:(?:(?:)))',
      );
      expect(
        regexpLexer(RegExp('')).tokenizer['root']!.single.name,
        'tokenizer.root: (?:)',
      );
    });

    test('attribute failures and invalid regexp syntax are not swallowed', () {
      expect(
        () => regexpLexer('@missing'),
        throwsA(_errorContaining("does not contain attribute 'missing'")),
      );
      expect(
        () => regexpLexer('@bad', attributes: {'bad': null}),
        throwsA(_errorContaining("attribute reference 'bad' must be a string")),
      );
      expect(
        () => regexpLexer(
          '@bad',
          attributes: {
            'bad': ['x'],
          },
        ),
        throwsA(_errorContaining("attribute reference 'bad' must be a string")),
      );
      expect(() => regexpLexer('['), throwsFormatException);
    });
  });

  group('Monarch action compilation', () {
    test(
      'short actions, falsy actions and grouped actions retain their forms',
      () {
        expect(
          _lexerForAction('token').tokenizer['root']!.single.action,
          'token',
        );
        for (final value in [null, '', false, 0, double.nan]) {
          expect(_action(value).token, '');
        }
        final action = _action([
          'first',
          {'token': 'second'},
          '',
        ]);
        expect(action.group!.length, 3);
        expect(action.group![0], 'first');
        expect((action.group![1] as IAction).token, 'second');
        expect((action.group![2] as IAction).token, '');
      },
    );

    test('copies only typed declarative fields and detects substitutions', () {
      final lexer = _lexerForAction({
        'token': r'token.$1',
        'bracket': '@open',
        'next': '@other.part',
        'goBack': 2,
        'switchTo': r'@root.$S2',
        'log': r'got $0',
        'nextEmbedded': 'javascript',
        'unknown': true,
        'transform': (List<String> values) => values,
      });
      final action = lexer.tokenizer['root']!.single.action as IAction;
      expect(action.token, r'token.$1');
      expect(action.tokenSubst, isTrue);
      expect(action.bracket, MonarchBracket.open);
      expect(action.next, 'other.part');
      expect(action.goBack, 2);
      expect(action.switchTo, r'@root.$S2');
      expect(action.log, r'got $0');
      expect(action.nextEmbedded, 'javascript');
      expect(action.transform, isNull);
      expect(lexer.usesEmbedded, isTrue);
      expect(
        _action({'token': 'x', 'bracket': '@close'}).bracket,
        MonarchBracket.close,
      );
      final untyped = _action({
        'token': '',
        'bracket': 1,
        'next': '',
        'goBack': '2',
        'switchTo': 1,
        'log': true,
        'nextEmbedded': false,
      });
      expect(untyped.bracket, isNull);
      expect(untyped.next, isNull);
      expect(untyped.goBack, isNull);
      expect(untyped.switchTo, isNull);
      expect(untyped.log, isNull);
      expect(untyped.nextEmbedded, isNull);
      expect(untyped.tokenSubst, isNull);
    });

    test(
      'validates static next states but defers dynamic next and switchTo',
      () {
        for (final next in ['@push', '@pop', '@popall', r'@missing.$1']) {
          expect(
            _action({'token': 'x', 'next': next}).next,
            next.startsWith('@missing') ? next.substring(1) : next,
          );
        }
        expect(
          _action({'token': 'x', 'switchTo': '@missing'}).switchTo,
          '@missing',
        );
        expect(
          () => _action({'token': 'x', 'next': '@missing'}),
          throwsA(_errorContaining("next state '@missing' is not defined")),
        );
        expect(
          () => _action({'token': 'x', 'next': 1}),
          throwsA(_errorContaining('next state must be a string')),
        );
      },
    );

    test('rejects unsupported actions and malformed token/bracket fields', () {
      for (final value in [
        {'token': 1},
        {'token': 'x', 'bracket': 'open'},
        {
          'group': ['a'],
        },
        {'next': '@pop'},
        1,
        () => 'token',
      ]) {
        expect(() => _action(value), throwsA(isA<MonarchError>()));
      }
    });

    test('recognizes nested embedded-end cases, including popall', () {
      for (final end in ['@pop', '@popall']) {
        final lexer = _lexerForAction({
          'cases': {
            '"""': {
              'cases': {
                '': {
                  'token': 'string.quote',
                  'next': '@popall',
                  'nextEmbedded': end,
                },
              },
            },
            '@default': '',
          },
        });
        final action = lexer.tokenizer['root']!.single.action as IAction;
        expect(lexer.usesEmbedded, isTrue);
        expect(action.hasEmbeddedEndInCases, isTrue);
        final nested = action.test!('"""', ['"""'], 'root', false) as IAction;
        expect(nested.hasEmbeddedEndInCases, isTrue);
        expect(
          (nested.test!('"""', ['"""'], 'root', false) as IAction).nextEmbedded,
          end,
        );
      }
    });

    test(
      'embedded-end metadata does not recurse into action groups upstream',
      () {
        final action = _action({
          'cases': {
            '@default': [
              {'token': '', 'nextEmbedded': '@pop'},
            ],
          },
        });
        expect(action.hasEmbeddedEndInCases, isFalse);
      },
    );
  });

  group('Monarch case guards', () {
    test('default aliases, fallthrough, ordering and end-of-stream', () {
      for (final key in ['@default', '@', '']) {
        expect(_case({key: 'fallback'}, 'text'), 'fallback');
      }
      expect(_case({}, 'text'), 'source');
      expect(
        _case({}, 'text', attributes: {'defaultToken': 'invalid'}),
        'invalid',
      );
      expect(_case({'@default': 'first', 'text': 'second'}, 'text'), 'first');
      expect(
        _case({'@eos': 'end', '@default': 'middle'}, 'text', eos: true),
        'end',
      );
      expect(_case({'@eos': 'end', '@default': 'middle'}, 'text'), 'middle');
    });

    test('keyword arrays and negations honor ignoreCase', () {
      const attributes = {
        'keywords': ['IF', 'else'],
        'ignoreCase': true,
      };
      for (final id in ['if', 'IF', 'else', 'ELSE']) {
        expect(
          _case({'@keywords': 'keyword'}, id, attributes: attributes),
          'keyword',
        );
        expect(
          _case({'!@keywords': 'other'}, id, attributes: attributes),
          'source',
        );
      }
      expect(
        _case({'!@keywords': 'other'}, 'name', attributes: attributes),
        'other',
      );
      expect(
        _case({'@keywords': 'keyword'}, 'if', attributes: {'keywords': []}),
        'source',
      );
      expect(
        () => _case({'@missing': 'token'}, 'id'),
        throwsA(_errorContaining("target 'missing' is not defined")),
      );
      expect(
        () => _case(
          {'@bad': 'token'},
          'id',
          attributes: {
            'bad': ['a', 1],
          },
        ),
        throwsA(_errorContaining('must be an array of strings')),
      );
    });

    test('word alternatives use the keyword fast path', () {
      expect(
        _case({'if|else': 'keyword'}, 'IF', attributes: {'ignoreCase': true}),
        'keyword',
      );
      expect(_case({'!~if|else': 'other'}, 'name'), 'other');
      expect(_case({'~': 'empty'}, ''), 'empty');
      expect(_case({'!~': 'nonempty'}, 'a'), 'nonempty');
    });

    test(
      'regex guards are anchored and support positive and negative tests',
      () {
        expect(_case({r'~[a-z]+': 'letters'}, 'abc'), 'letters');
        expect(_case({r'~[a-z]+': 'letters'}, 'abc2'), 'source');
        expect(_case({r'!~[a-z]+': 'other'}, '123'), 'other');
        expect(_case({r'!~[a-z]+': 'other'}, 'abc'), 'source');
        expect(
          _case(
            {r'~@letters+': 'letters'},
            'abc',
            attributes: {'letters': '[a-z]'},
          ),
          'letters',
        );
      },
    );

    test('equality guards preserve the source case-folding asymmetry', () {
      expect(_case({'word': 'yes'}, 'word'), 'yes');
      expect(_case({'==word': 'yes'}, 'word'), 'yes');
      expect(_case({'!=word': 'yes'}, 'other'), 'yes');
      expect(
        _case({'WORD': 'yes'}, 'word', attributes: {'ignoreCase': true}),
        'yes',
      );
      // Only the pattern is lowercased for equality, unlike keyword/regex guards.
      expect(
        _case({'WORD': 'yes'}, 'WORD', attributes: {'ignoreCase': true}),
        'source',
      );
    });

    test('scrutinees select ID, captures, full state and state components', () {
      const captures = ['full', 'first', null, ''];
      expect(_case({r'$#==id': 'yes'}, 'id', matches: captures), 'yes');
      expect(_case({r'$0==full': 'yes'}, 'id', matches: captures), 'yes');
      expect(_case({r'$1==first': 'yes'}, 'id', matches: captures), 'yes');
      expect(_case({r'$2==': 'yes'}, 'id', matches: captures), 'yes');
      expect(_case({r'$99==': 'yes'}, 'id', matches: captures), 'yes');
      expect(
        _case({r'$S0==root.child': 'yes'}, 'id', state: 'root.child'),
        'yes',
      );
      expect(_case({r'$s1==root': 'yes'}, 'id', state: 'root.child'), 'yes');
      expect(_case({r'$S2==child': 'yes'}, 'id', state: 'root.child'), 'yes');
      expect(_case({r'$S99==': 'yes'}, 'id', state: 'root.child'), 'yes');
      expect(_case({r'$1': 'nonempty'}, 'id', matches: captures), 'nonempty');
      expect(_case({r'$3': 'nonempty'}, 'id', matches: captures), 'source');
    });

    test('substitutions in equality and regex guards are evaluated at runtime', () {
      expect(
        _case(
          {r'$1==$S2': 'same'},
          'all',
          matches: ['all', 'tag'],
          state: 'root.tag',
        ),
        'same',
      );
      expect(
        _case(
          {r'$1!=$S2': 'different'},
          'all',
          matches: ['all', 'other'],
          state: 'root.tag',
        ),
        'different',
      );
      expect(_case({r'~$S2': 'matches'}, 'aaaa', state: 'root.a+'), 'matches');
      // This surprising positive match for dynamic !~ is in the pinned source.
      expect(_case({r'!~$S2': 'matches'}, 'aaaa', state: 'root.a+'), 'matches');
      expect(_case({r'!~$S2': 'matches'}, 'bbb', state: 'root.a+'), 'source');
    });
  });

  group('Monarch brackets', () {
    test('default bracket configuration and token postfix', () {
      final lexer = compile('test', {
        'tokenizer': {'root': []},
      });
      expect(
        lexer.brackets.map(
          (bracket) => [bracket.open, bracket.close, bracket.token],
        ),
        [
          ['{', '}', 'delimiter.curly.test'],
          ['[', ']', 'delimiter.square.test'],
          ['(', ')', 'delimiter.parenthesis.test'],
          ['<', '>', 'delimiter.angle.test'],
        ],
      );
    });

    test(
      'list and map bracket forms, case folding and empty configuration',
      () {
        final lexer = compile('test', {
          'ignoreCase': true,
          'tokenPostfix': '.custom',
          'brackets': [
            ['BEGIN', 'END', 'keyword'],
            {'open': 'IF', 'close': 'FI', 'token': 'delimiter'},
            ['CASE', 'case', 'sameAfterFold'],
          ],
          'tokenizer': {'root': []},
        });
        expect(
          lexer.brackets.map(
            (bracket) => [bracket.open, bracket.close, bracket.token],
          ),
          [
            ['begin', 'end', 'keyword.custom'],
            ['if', 'fi', 'delimiter.custom'],
            ['case', 'case', 'sameAfterFold.custom'],
          ],
        );
        expect(
          compile('test', {
            'brackets': [],
            'tokenizer': {'root': []},
          }).brackets,
          isEmpty,
        );
      },
    );

    test('rejects non-array, equal or malformed bracket definitions', () {
      for (final brackets in [
        'bad',
        [
          ['same', 'same', 'token'],
        ],
        [
          ['a', 'b', 1],
        ],
        [
          {'open': 'a', 'token': 'token'},
        ],
      ]) {
        expect(
          () => compile('test', {
            'brackets': brackets,
            'tokenizer': {'root': []},
          }),
          throwsA(isA<MonarchError>()),
        );
      }
    });
  });
}
