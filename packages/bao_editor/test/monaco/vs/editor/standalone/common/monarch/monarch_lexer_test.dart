/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See lib/monaco/LICENSE.txt.
 *--------------------------------------------------------------------------------------------*/
// Upstream regression cases ported from VS Code
// src/vs/editor/standalone/test/browser/monarch.test.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971, plus action/state/adapter coverage.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/vs/editor/common/encoded_token_attributes.dart';
import 'package:bao_editor/monaco/vs/editor/standalone/common/monarch/monarch_common.dart';
import 'package:bao_editor/monaco/vs/editor/standalone/common/monarch/monarch_compile.dart';
import 'package:bao_editor/monaco/vs/editor/standalone/common/monarch/monarch_lexer.dart';

MonarchTokenizer _tokenizer(
  Map<String, Object?> language, {
  String id = 'test',
}) => MonarchTokenizer(id, compile(id, language));

List<(int, String, String)> _view(TokenizationResult result) => [
  for (final token in result.tokens) (token.offset, token.type, token.language),
];

List<List<(int, String, String)>> _lines(
  MonarchTokenizer tokenizer,
  List<String> lines,
) {
  IState state = tokenizer.getInitialState();
  return [
    for (final line in lines)
      (() {
        final result = tokenizer.tokenize(line, true, state);
        state = result.endState;
        return _view(result);
      })(),
  ];
}

List<(int, String, String)> _once(MonarchTokenizer tokenizer, String line) =>
    _view(tokenizer.tokenize(line, true, tokenizer.getInitialState()));

Matcher _error(String text) => throwsA(
  isA<MonarchError>().having((e) => e.message, 'message', contains(text)),
);

final class _CounterState implements IState {
  const _CounterState(this.value, {this.mutableClone = false});
  final int value;
  final bool mutableClone;

  @override
  IState clone() =>
      mutableClone ? _CounterState(value, mutableClone: true) : this;

  @override
  bool equals(IState other) => other is _CounterState && value == other.value;
}

final class _RecordingSupport implements ITokenizationSupport {
  final calls = <(String, bool, int)>[];

  @override
  IState getInitialState() => const _CounterState(0);

  @override
  TokenizationResult tokenize(String line, bool hasEOL, IState lineState) {
    final value = (lineState as _CounterState).value;
    calls.add((line, hasEOL, value));
    return TokenizationResult([
      if (line.isNotEmpty) const Token(0, 'nested', 'nested'),
    ], _CounterState(value + 1));
  }

  @override
  EncodedTokenizationResult tokenizeEncoded(
    String line,
    bool hasEOL,
    IState lineState,
  ) {
    final result = tokenize(line, hasEOL, lineState);
    return EncodedTokenizationResult(
      Uint32List.fromList(line.isEmpty ? [] : [0, 0x02018003]),
      result.endState,
    );
  }
}

final class _Rule implements IRule {
  _Rule(this.action);
  @override
  final FuzzyAction action;
  @override
  bool get matchOnlyAtLineStart => false;
  @override
  String get name => 'test rule';
  @override
  RegExp resolveRegex(String state) => RegExp('^(?:.)');
}

Map<String, Object?> _embeddedGrammar({
  String end = '>',
  String id = 'nested',
}) => {
  'tokenizer': {
    'root': [
      [
        '<',
        {'token': 'delimiter', 'next': '@embedded', 'nextEmbedded': id},
      ],
      ['.', 'outer'],
    ],
    'embedded': [
      [
        end,
        {'token': 'delimiter', 'next': '@pop', 'nextEmbedded': '@pop'},
      ],
    ],
  },
};

void main() {
  group('pinned upstream Monarch regressions', () {
    for (final popInCases in [false, true]) {
      test('@rematch + nextEmbedded; pop in cases = $popInCases', () {
        final sql = _tokenizer({
          'tokenizer': {
            'root': [
              ['.', 'token'],
            ],
          },
        }, id: 'sql');
        const queryStart =
            '(SELECT|INSERT|UPDATE|DELETE|CREATE|REPLACE|ALTER|WITH)';
        final language = <String, Object?>{
          'tokenizer': {
            'root': [
              [
                '(""")$queryStart',
                [
                  {'token': 'string.quote'},
                  {
                    'token': '@rematch',
                    'next': '@endStringWithSQL',
                    'nextEmbedded': 'sql',
                  },
                ],
              ],
              [
                r'(""")$',
                [
                  {'token': 'string.quote', 'next': '@maybeStringIsSQL'},
                ],
              ],
            ],
            'maybeStringIsSQL': [
              [
                '(.*)',
                {
                  'cases': {
                    '$queryStart\\b.*': {
                      'token': '@rematch',
                      'next': '@endStringWithSQL',
                      'nextEmbedded': 'sql',
                    },
                    '@default': {
                      'token': '@rematch',
                      'switchTo': '@endDblDocString',
                    },
                  },
                },
              ],
            ],
            'endDblDocString': [
              ["[^']+", 'string'],
              [r"\'", 'string'],
              ["'''", 'string', '@popall'],
              ["'", 'string'],
            ],
            'endStringWithSQL': [
              [
                '"""',
                popInCases
                    ? {
                        'cases': {
                          '"""': {
                            'cases': {
                              '': {
                                'token': 'string.quote',
                                'next': '@popall',
                                'nextEmbedded': '@pop',
                              },
                            },
                          },
                          '@default': '',
                        },
                      }
                    : {
                        'token': 'string.quote',
                        'next': '@popall',
                        'nextEmbedded': '@pop',
                      },
              ],
            ],
          },
        };
        final tokenizer = MonarchTokenizer(
          'test1',
          compile('test1', language),
          embeddingSupport: MonarchEmbeddingSupport(
            getTokenizationSupport: (id) => id == 'sql' ? sql : null,
          ),
        );
        expect(
          _lines(tokenizer, [
            'mysql_query("""SELECT * FROM table_name WHERE ds = \'<DATEID>\'""")',
            'mysql_query("""',
            'SELECT *',
            'FROM table_name',
            "WHERE ds = '<DATEID>'",
            '""")',
          ]),
          [
            [
              (0, 'source.test1', 'test1'),
              (12, 'string.quote.test1', 'test1'),
              (15, 'token.sql', 'sql'),
              (61, 'string.quote.test1', 'test1'),
              (64, 'source.test1', 'test1'),
            ],
            [(0, 'source.test1', 'test1'), (12, 'string.quote.test1', 'test1')],
            [(0, 'token.sql', 'sql')],
            [(0, 'token.sql', 'sql')],
            [(0, 'token.sql', 'sql')],
            [(0, 'string.quote.test1', 'test1'), (3, 'source.test1', 'test1')],
          ],
        );
      });
    }

    test('#1235 empty lines can pop continued comment states', () {
      final tokenizer = _tokenizer({
        'tokenizer': {
          'root': [
            {'include': '@comments'},
          ],
          'comments': [
            [r'//$', 'comment'],
            ['//', 'comment', '@comment_cpp'],
          ],
          'comment_cpp': [
            [r'(?:[^\\]|(?:\\.))+$', 'comment', '@pop'],
            [r'.+$', 'comment'],
            [r'$', 'comment', '@pop'],
          ],
        },
      });
      final tokens = _lines(tokenizer, [
        '// This comment \\',
        '   continues on the following line',
        '',
        '// This comment does NOT continue \\\\',
        '   because the escape char was itself escaped',
        '',
        '// This comment DOES continue because \\\\\\',
        "   the 1st '\\' escapes the 2nd; the 3rd escapes EOL",
        '',
        '// This comment continues to the following line \\',
        '',
        'But the line was empty. This line should not be commented.',
      ]);
      expect(tokens, [
        [(0, 'comment.test', 'test')],
        [(0, 'comment.test', 'test')],
        [],
        [(0, 'comment.test', 'test')],
        [(0, 'source.test', 'test')],
        [],
        [(0, 'comment.test', 'test')],
        [(0, 'comment.test', 'test')],
        [],
        [(0, 'comment.test', 'test')],
        [],
        [(0, 'source.test', 'test')],
      ]);
    });

    test('#2265 includeLF exits state without emitting the synthetic LF', () {
      final tokenizer = _tokenizer({
        'includeLF': true,
        'tokenizer': {
          'root': [
            [r'^\*', '', '@inner'],
            [r':\*', '', '@inner'],
            ['[^*:]+', 'string'],
            ['[*:]', 'string'],
          ],
          'inner': [
            [r'\n', '', '@pop'],
            [r'\d+', 'number'],
            [r'[^\d]+', ''],
          ],
        },
      });
      expect(
        _lines(tokenizer, [
          'PRINT 10 * 20',
          '*FX200, 3',
          'PRINT 2*3:*FX200, 3',
        ]),
        [
          [(0, 'string.test', 'test')],
          [
            (0, '', 'test'),
            (3, 'number.test', 'test'),
            (6, '', 'test'),
            (8, 'number.test', 'test'),
          ],
          [
            (0, 'string.test', 'test'),
            (9, '', 'test'),
            (13, 'number.test', 'test'),
            (16, '', 'test'),
            (18, 'number.test', 'test'),
          ],
        ],
      );
      final result = tokenizer.tokenize(
        '*1',
        false,
        tokenizer.getInitialState(),
      );
      expect((result.endState as MonarchLineState).stack.state, 'inner');
    });

    test('#115662 nested regex attributes and @@ escapes', () {
      for (final attributes in [true, false]) {
        final tokenizer = _tokenizer({
          if (attributes) ...{
            'uselessReplaceKey1': '@uselessReplaceKey2',
            'uselessReplaceKey2': '@uselessReplaceKey3',
            'uselessReplaceKey3': '@uselessReplaceKey4',
            'uselessReplaceKey4': '@uselessReplaceKey5',
            'uselessReplaceKey5': '@ham',
          },
          'tokenizer': {
            'root': [
              [
                attributes ? r'^@uselessReplaceKey1$' : '@@ham',
                {'token': 'ham'},
              ],
            ],
          },
        });
        expect(_once(tokenizer, '@ham'), [(0, 'ham.test', 'test')]);
      }
    });

    test('#2424 literal @@', () {
      expect(
        _once(
          _tokenizer({
            'tokenizer': {
              'root': [
                [
                  '@@@@',
                  {'token': 'ham'},
                ],
              ],
            },
          }),
          '@@',
        ),
        [(0, 'ham.test', 'test')],
      );
    });

    test(
      '#3025 length limit checked before tokenization, including equality',
      () {
        final tokenizer = _tokenizer({
          'tokenizer': {
            'root': [
              ['ham', 'ham'],
            ],
          },
        })..maxTokenizationLineLength = 4;
        expect(_lines(tokenizer, ['ham', 'hamham', 'hamm']), [
          [(0, 'ham.test', 'test')],
          [(0, '', 'test')],
          [(0, '', 'test')],
        ]);
        final initial = tokenizer.getInitialState();
        expect(
          identical(
            tokenizer.tokenize('hamm', true, initial).endState,
            initial,
          ),
          isTrue,
        );
        tokenizer.maxTokenizationLineLength = 8;
        expect(_once(tokenizer, 'hamham'), [(0, 'ham.test', 'test')]);
      },
    );

    for (final escaping in [false, true]) {
      test(
        escaping
            ? '#4775 raw string state is regex escaped'
            : '#3128 state substitutions in regex',
        () {
          final tokenizer = _tokenizer({
            'encoding': RegExp('u|u8|U|L'),
            'tokenizer': {
              'root': [
                [
                  r'@encoding?R"(?:([^ ()\\\t]*))\(',
                  {'token': 'string.raw.begin', 'next': r'@raw.$1'},
                ],
              ],
              'raw': [
                [r'.*\)$S2"', 'string.raw', '@pop'],
                ['.*', 'string.raw'],
              ],
            },
          });
          if (escaping) {
            expect(_once(tokenizer, 'R"[())"'), [
              (0, 'string.raw.begin.test', 'test'),
              (4, 'string.raw.test', 'test'),
            ]);
          } else {
            expect(
              _lines(tokenizer, [
                'int main(){',
                '',
                '\tauto s = R""""(',
                '\tHello World',
                '\t)"""";',
                '',
                '\tstd::cout << "hello";',
                '',
                '}',
              ]),
              [
                [(0, 'source.test', 'test')],
                [],
                [
                  (0, 'source.test', 'test'),
                  (10, 'string.raw.begin.test', 'test'),
                ],
                [(0, 'string.raw.test', 'test')],
                [(0, 'string.raw.test', 'test'), (6, 'source.test', 'test')],
                [],
                [(0, 'source.test', 'test')],
                [],
                [(0, 'source.test', 'test')],
              ],
            );
          }
        },
      );
    }
  });

  group('stacks and incremental line states', () {
    test('persistent stacks compare structurally beyond the cache depth', () {
      var a = MonarchStackElement(null, 'root');
      var b = MonarchStackElement(null, 'root');
      for (var i = 0; i < 8; i++) {
        a = a.push('s$i');
        b = b.push('s$i');
      }
      expect(identical(a, b), isFalse);
      expect(a.equals(b), isTrue);
      expect(a.depth, 9);
      expect(a.switchTo('changed').depth, 9);
      expect(a.equals(a.switchTo('changed')), isFalse);
      expect(a.pop()!.state, 's6');
      expect(a.popall().state, 'root');
      expect(a.popall().pop(), isNull);
      expect(
        MonarchStackElement.getStackElementId(a),
        's7|s6|s5|s4|s3|s2|s1|s0|root',
      );
    });

    test('push, pop, popall, switchTo and multiline comment recovery', () {
      final tokenizer = _tokenizer({
        'tokenizer': {
          'root': [
            [r'/\*', 'comment', '@comment'],
            ['.', 'text'],
          ],
          'comment': [
            [r'/\*', 'comment', '@push'],
            [r'\*/', 'comment', '@pop'],
            [
              '!',
              {'token': 'comment', 'switchTo': '@other'},
            ],
            ['.', 'comment'],
          ],
          'other': [
            [';', 'comment', '@popall'],
            ['.', 'comment'],
          ],
        },
      });
      final initial = tokenizer.getInitialState();
      expect(identical(initial, tokenizer.getInitialState()), isTrue);
      expect(identical(initial.clone(), initial), isTrue);
      var result = tokenizer.tokenize('a/* one /*', true, initial);
      var state = result.endState as MonarchLineState;
      expect(state.stack.depth, 3);
      expect(initial.stack.depth, 1);
      expect(_view(result), [
        (0, 'text.test', 'test'),
        (1, 'comment.test', 'test'),
      ]);
      result = tokenizer.tokenize('two */!', true, state);
      state = result.endState as MonarchLineState;
      expect(state.stack.state, 'other');
      expect(state.stack.depth, 2);
      result = tokenizer.tokenize('end;b', true, state);
      expect(_view(result), [
        (0, 'comment.test', 'test'),
        (4, 'text.test', 'test'),
      ]);
      expect(result.endState.equals(initial), isTrue);
      expect(state.equals(initial), isFalse);
      expect(initial.equals(nullState), isFalse);
    });

    test('embedded equality and pinned clone behavior', () {
      final stack = MonarchStackElement(null, 'root');
      const embedded = EmbeddedLanguageData('nested', _CounterState(1));
      final state = MonarchLineState(stack, embedded);
      expect(identical(state.clone(), state), isTrue);
      expect(
        state.equals(
          MonarchLineState(
            stack,
            const EmbeddedLanguageData('nested', _CounterState(1)),
          ),
        ),
        isTrue,
      );
      expect(
        state.equals(
          MonarchLineState(
            stack,
            const EmbeddedLanguageData('other', _CounterState(1)),
          ),
        ),
        isFalse,
      );
      expect(
        state.equals(
          MonarchLineState(
            stack,
            const EmbeddedLanguageData('nested', _CounterState(2)),
          ),
        ),
        isFalse,
      );
      expect(state.equals(MonarchLineState(stack, null)), isFalse);
      final mutable = MonarchLineState(
        stack,
        const EmbeddedLanguageData(
          'nested',
          _CounterState(1, mutableClone: true),
        ),
      );
      final cloned = mutable.clone();
      expect(identical(cloned, mutable), isFalse);
      // This is intentionally upstream's shallow-clone quirk.
      expect(
        identical(cloned.embeddedLanguageData, mutable.embeddedLanguageData),
        isTrue,
      );
    });
  });

  group('captures and actions', () {
    test('group actions retain whole-match captures after state changes', () {
      final tokenizer = _tokenizer({
        'tokenizer': {
          'root': [
            [
              r'(A)(:)(B)',
              [
                {'token': r'first.$3', 'next': r'@part.$1'},
                {'token': r'middle.$S2'},
                {'token': r'last.$1.$3', 'next': '@pop'},
              ],
            ],
          ],
          'part': [],
        },
      });
      expect(_once(tokenizer, 'A:B'), [
        (0, 'first.B.test', 'test'),
        (1, 'middle.A.test', 'test'),
        (2, 'last.A.B.test', 'test'),
      ]);
    });

    test('ordered cases, keyword lists, substitutions and end-of-stream', () {
      final tokenizer = _tokenizer({
        'ignoreCase': true,
        'keywords': ['IF'],
        'tokenizer': {
          'root': [
            [
              r'\w+',
              {
                'cases': {
                  '@keywords': 'keyword',
                  '@eos': {'token': r'end.$#'},
                  '@default': 'word',
                },
              },
            ],
            [r'\s+', ''],
          ],
        },
      });
      expect(_once(tokenizer, 'IF hello LAST'), [
        (0, 'keyword.test', 'test'),
        (2, '', 'test'),
        (3, 'word.test', 'test'),
        (8, '', 'test'),
        (9, 'end.last.test', 'test'),
      ]);
    });

    test('goBack reprocesses a suffix in the pushed state', () {
      final tokenizer = _tokenizer({
        'tokenizer': {
          'root': [
            [
              'ab',
              {'token': 'head', 'goBack': 1, 'next': '@tail'},
            ],
          ],
          'tail': [
            ['b', 'tail', '@pop'],
          ],
        },
      });
      expect(_once(tokenizer, 'abab'), [
        (0, 'head.test', 'test'),
        (1, 'tail.test', 'test'),
        (2, 'head.test', 'test'),
        (3, 'tail.test', 'test'),
      ]);
    });

    test('rematch and zero-length matches require a state change', () {
      for (final pattern in ['', r'\d']) {
        final tokenizer = _tokenizer({
          'tokenizer': {
            'root': [
              [
                pattern,
                {'token': '@rematch', 'switchTo': '@number'},
              ],
            ],
            'number': [
              [r'\d+', 'number'],
            ],
          },
        });
        expect(_once(tokenizer, '123'), [(0, 'number.test', 'test')]);
      }
      final noProgress = _tokenizer({
        'tokenizer': {
          'root': [
            ['', 'bad'],
          ],
        },
      });
      expect(() => _once(noProgress, 'x'), _error('no progress'));
      expect(_once(noProgress, ''), isEmpty);
      final rematch = _tokenizer({
        'tokenizer': {
          'root': [
            ['.', '@rematch'],
          ],
        },
      });
      expect(() => _once(rematch, 'x'), _error('no progress'));
    });

    test(
      'brackets resolve case-insensitively and token scopes are sanitized',
      () {
        final tokenizer = _tokenizer({
          'ignoreCase': true,
          'brackets': [
            ['begin', 'end', 'delimiter_block'],
          ],
          'tokenizer': {
            'root': [
              ['begin|end', '@brackets.extra'],
              [r'\s+', ''],
              ['.', 'odd_<&>'],
            ],
          },
        });
        expect(_once(tokenizer, 'BEGIN x END'), [
          (0, 'delimiter-block.test.extra', 'test'),
          (5, '', 'test'),
          (6, 'odd----.test', 'test'),
          (7, '', 'test'),
          (8, 'delimiter-block.test.extra', 'test'),
        ]);
        final missing = _tokenizer({
          'brackets': <Object>[],
          'tokenizer': {
            'root': [
              ['.', '@brackets'],
            ],
          },
        });
        expect(() => _once(missing, '?'), _error('no bracket defined as: ?'));
      },
    );

    test('UTF-16 offsets including astral matches and unmatched fallback', () {
      final tokenizer = _tokenizer({
        'unicode': true,
        'tokenizer': {
          'root': [
            ['😀', 'face'],
            ['x', 'letter'],
          ],
        },
      });
      expect(_once(tokenizer, '😀x🙂x'), [
        (0, 'face.test', 'test'),
        (2, 'letter.test', 'test'),
        (3, 'source.test', 'test'),
        (5, 'letter.test', 'test'),
      ]);
    });

    test('logging uses explicit callback and upstream double prefix', () {
      final logs = <String>[];
      final lexer = compile('test', {
        'tokenizer': {
          'root': [
            [
              '(x)',
              {'token': '', 'log': r'matched $1 in $S0'},
            ],
          ],
        },
      });
      final tokenizer = MonarchTokenizer('test', lexer, onLog: logs.add);
      expect(_once(tokenizer, 'x'), [(0, '', 'test')]);
      expect(logs, ['test: test: matched x in root']);
    });

    test(
      'invalid group counts, coverage, nesting and absent captures fail',
      () {
        for (final rule in <List<Object>>[
          [
            '(a)(b)',
            ['one'],
          ],
          [
            '(a)b',
            ['one'],
          ],
          [
            '((a))',
            ['one', 'two'],
          ],
        ]) {
          final tokenizer = _tokenizer({
            'tokenizer': {
              'root': [rule],
            },
          });
          expect(() => _once(tokenizer, 'ab'), throwsA(isA<MonarchError>()));
        }
        final nested = _tokenizer({
          'tokenizer': {
            'root': [
              [
                '(a)(b)',
                [
                  ['inner'],
                  'outer',
                ],
              ],
            ],
          },
        });
        expect(() => _once(nested, 'ab'), _error('groups cannot be nested'));
        final absent = _tokenizer({
          'tokenizer': {
            'root': [
              [
                '(a)?(b)',
                ['a', 'b'],
              ],
            ],
          },
        });
        expect(() => _once(absent, 'b'), throwsA(isA<TypeError>()));
      },
    );

    test('stack underflow, push limit and dynamic nonexistent states fail', () {
      final pop = _tokenizer({
        'tokenizer': {
          'root': [
            ['.', '', '@pop'],
          ],
        },
      });
      expect(() => _once(pop, 'x'), _error('trying to pop an empty stack'));
      final push = _tokenizer({
        'tokenizer': {
          'root': [
            ['.', '', '@push'],
          ],
        },
      });
      push.lexer.maxStack = 3;
      expect(() => _once(push, 'abc'), _error('maximum tokenizer stack size'));
      for (final field in ['next', 'switchTo']) {
        final missing = _tokenizer({
          'tokenizer': {
            'root': [
              [
                '(missing)',
                {'token': 'x', field: r'@$1'},
              ],
            ],
          },
        });
        expect(
          () => _once(missing, 'missing'),
          _error("state 'missing' that is undefined"),
        );
      }
    });

    test(
      'compiled transform and fractional goBack are explicitly unsupported',
      () {
        final lexer = compile('test', {
          'tokenizer': {
            'root': [
              ['.', 'x'],
            ],
          },
        });
        lexer.tokenizer['root'] = [
          _Rule(IAction(token: 'x', transform: (stack) => stack)),
        ];
        final tokenizer = MonarchTokenizer('test', lexer);
        expect(
          () => _once(tokenizer, 'x'),
          _error('action.transform not supported'),
        );
        lexer.tokenizer['root'] = [
          _Rule(const IAction(token: 'x', goBack: 0.5)),
        ];
        expect(
          () => _once(tokenizer, 'x'),
          _error('goBack must be a finite integer'),
        );
      },
    );
  });

  group('explicit embedded-language contracts', () {
    test('nested states, split-line hasEOL and outer offsets', () {
      final nested = _RecordingSupport();
      final requests = <String>[];
      final tokenizer = MonarchTokenizer(
        'test',
        compile('test', _embeddedGrammar()),
        embeddingSupport: MonarchEmbeddingSupport(
          getTokenizationSupport: (id) => id == 'nested' ? nested : null,
          requestBasicLanguageFeatures: requests.add,
        ),
      );
      var result = tokenizer.tokenize(
        'a<one',
        true,
        tokenizer.getInitialState(),
      );
      expect(_view(result), [
        (0, 'outer.test', 'test'),
        (1, 'delimiter.test', 'test'),
        (2, 'nested', 'nested'),
      ]);
      result = tokenizer.tokenize('two', true, result.endState);
      result = tokenizer.tokenize('three>b', true, result.endState);
      expect(_view(result), [
        (0, 'nested', 'nested'),
        (5, 'delimiter.test', 'test'),
        (6, 'outer.test', 'test'),
      ]);
      expect(nested.calls, [
        ('one', true, 0),
        ('two', true, 1),
        ('three', false, 2),
      ]);
      expect(result.endState.equals(tokenizer.getInitialState()), isTrue);
      expect(requests, ['nested']);
      expect(tokenizer.embeddedLanguages, {'nested'});
      expect(tokenizer.getLoadStatus().loaded, isTrue);
    });

    test('language name takes precedence over MIME type and literal ID', () {
      final nested = _RecordingSupport();
      final nameLookups = <String>[];
      final mimeLookups = <String>[];
      final tokenizer = MonarchTokenizer(
        'test',
        compile('test', _embeddedGrammar(id: 'Nested')),
        embeddingSupport: MonarchEmbeddingSupport(
          getTokenizationSupport: (id) => id == 'nested' ? nested : null,
          languageIdByName: (name) {
            nameLookups.add(name);
            return 'nested';
          },
          languageIdByMimeType: (mime) {
            mimeLookups.add(mime);
            return null;
          },
        ),
      );
      _once(tokenizer, '<a>');
      expect(nameLookups, ['Nested']);
      expect(mimeLookups, isEmpty);
      final mimeTokenizer = MonarchTokenizer(
        'test',
        compile('test', _embeddedGrammar(id: 'text/nested')),
        embeddingSupport: MonarchEmbeddingSupport(
          getTokenizationSupport: (id) => id == 'nested' ? nested : null,
          languageIdByName: (_) => null,
          languageIdByMimeType: (mime) =>
              mime == 'text/nested' ? 'nested' : null,
        ),
      );
      expect(_once(mimeTokenizer, '<x>'), [
        (0, 'delimiter.test', 'test'),
        (1, 'nested', 'nested'),
        (2, 'delimiter.test', 'test'),
      ]);
    });

    test('unknown embedding uses null state/tokens and can exit', () {
      final tokenizer = _tokenizer(_embeddedGrammar(id: 'unknown'));
      var result = tokenizer.tokenize('<', true, tokenizer.getInitialState());
      final state = result.endState as MonarchLineState;
      expect(state.embeddedLanguageData!.state, same(nullState));
      result = tokenizer.tokenize('abc>', true, state);
      expect(_view(result), [
        (0, '', 'unknown'),
        (3, 'delimiter.test', 'test'),
      ]);
      expect(result.endState.equals(tokenizer.getInitialState()), isTrue);
      expect(tokenizer.embeddedLanguages, isEmpty);
    });

    test(
      'empty remainder does not call nested support; line-start pop anchoring',
      () {
        final nested = _RecordingSupport();
        final tokenizer = MonarchTokenizer(
          'test',
          compile('test', _embeddedGrammar(end: '^>')),
          embeddingSupport: MonarchEmbeddingSupport(
            getTokenizationSupport: (_) => nested,
          ),
        );
        var state = tokenizer
            .tokenize('<', true, tokenizer.getInitialState())
            .endState;
        expect(nested.calls, isEmpty);
        state = tokenizer.tokenize('x>', true, state).endState;
        expect(nested.calls, [('x>', true, 0)]);
        final result = tokenizer.tokenize('>x', true, state);
        expect(_view(result), [
          (0, 'delimiter.test', 'test'),
          (1, 'outer.test', 'test'),
        ]);
        expect(nested.calls, [('x>', true, 0)]);
      },
    );

    test(
      'asynchronous loader status is explicit, including recursively',
      () async {
        final loaded = Completer<void>();
        var resolved = false;
        final requests = <String>[];
        final tokenizer = MonarchTokenizer(
          'test',
          compile('test', _embeddedGrammar()),
          embeddingSupport: MonarchEmbeddingSupport(
            getTokenizationSupport: (_) => null,
            isRegisteredLanguageId: (_) => true,
            isResolved: (_) => resolved,
            loadLanguage: (id) {
              requests.add(id);
              return loaded.future;
            },
          ),
        );
        _once(tokenizer, '<');
        final status = tokenizer.getLoadStatus();
        expect(status.loaded, isFalse);
        final outer = MonarchTokenizer(
          'outer',
          compile('outer', _embeddedGrammar(id: 'test')),
          embeddingSupport: MonarchEmbeddingSupport(
            getTokenizationSupport: (_) => tokenizer,
          ),
        );
        _once(outer, '<');
        final outerStatus = outer.getLoadStatus();
        expect(outerStatus.loaded, isFalse);
        resolved = true;
        loaded.complete();
        await status.promise;
        await outerStatus.promise;
        expect(tokenizer.getLoadStatus().loaded, isTrue);
        expect(outer.getLoadStatus().loaded, isTrue);
        expect(requests, ['nested', 'nested', 'nested']);
      },
    );

    test(
      'missing pop rule, pop outside embed and double embed are rejected',
      () {
        final missing = _tokenizer({
          'tokenizer': {
            'root': [
              [
                '<',
                {'token': '', 'next': '@embedded', 'nextEmbedded': 'unknown'},
              ],
            ],
            'embedded': [
              ['.', 'x'],
            ],
          },
        });
        expect(
          () => _once(missing, '<x'),
          _error('no rule containing nextEmbedded'),
        );
        final pop = _tokenizer({
          'tokenizer': {
            'root': [
              [
                '.',
                {'token': '', 'nextEmbedded': '@pop'},
              ],
            ],
          },
        });
        expect(() => _once(pop, 'x'), _error('cannot pop embedded language'));
        final doubleEmbed = _tokenizer({
          'tokenizer': {
            'root': [
              [
                '<',
                {'token': '', 'next': '@embedded', 'nextEmbedded': 'unknown'},
              ],
            ],
            'embedded': [
              [
                '>',
                {'token': '', 'nextEmbedded': 'again'},
              ],
              [
                '>',
                {'token': '', 'nextEmbedded': '@pop'},
              ],
            ],
          },
        });
        expect(
          () => _once(doubleEmbed, '<>'),
          _error('cannot enter embedded language from within'),
        );
      },
    );
  });

  group('encoded collectors and token metadata adapters', () {
    final theme = MonarchTokenTheme(
      encodeLanguageId: (id) => id == 'test' ? 2 : 3,
      match: (id, token) =>
          id | (token.startsWith('delimiter') ? 0xff010000 : 0xff008000),
    );

    test(
      'explicit theme required; metadata coalesces scopes and sets bracket bit',
      () {
        final lexer = compile('test', {
          'tokenizer': {
            'root': [
              ['a', 'one'],
              ['b', 'two'],
            ],
          },
        });
        final tokenizer = MonarchTokenizer('test', lexer, tokenTheme: theme);
        final result = tokenizer.tokenizeEncoded(
          'ab',
          true,
          tokenizer.getInitialState(),
        );
        expect(result.tokens, [0, 0xff008402]);
        expect(result.fontInfo, isEmpty);
        expect(result.endState.equals(tokenizer.getInitialState()), isTrue);
        expect(
          tokenizer
              .tokenizeEncoded('', true, tokenizer.getInitialState())
              .tokens,
          isEmpty,
        );
        final classic = MonarchTokenizer('test', lexer);
        expect(
          () => classic.tokenizeEncoded('ab', true, classic.getInitialState()),
          throwsStateError,
        );
      },
    );

    test(
      'encoded long-line fallback preserves state and uses default colors',
      () {
        final tokenizer = MonarchTokenizer(
          'test',
          compile('test', {
            'tokenizer': {
              'root': [
                ['.', 'text'],
              ],
            },
          }),
          tokenTheme: theme,
          maxTokenizationLineLength: 3,
        );
        final state = tokenizer.getInitialState();
        final result = tokenizer.tokenizeEncoded('abc', true, state);
        expect(result.tokens, [0, 0x02008002]);
        expect(
          TokenMetadata.containsBalancedBrackets(result.tokens[1]),
          isFalse,
        );
        expect(result.endState, same(state));
      },
    );

    test('embedded encoded arrays merge and rebase their start offsets', () {
      final nested = _RecordingSupport();
      final tokenizer = MonarchTokenizer(
        'test',
        compile('test', _embeddedGrammar()),
        tokenTheme: theme,
        embeddingSupport: MonarchEmbeddingSupport(
          getTokenizationSupport: (_) => nested,
        ),
      );
      final result = tokenizer.tokenizeEncoded(
        'a<xy>b',
        true,
        tokenizer.getInitialState(),
      );
      expect(result.tokens, [
        0,
        0xff008402,
        1,
        0xff010402,
        2,
        0x02018003,
        4,
        0xff010402,
        5,
        0xff008402,
      ]);
      expect(nested.calls, [('xy', false, 0)]);
      expect(result.endState.equals(tokenizer.getInitialState()), isTrue);
    });

    test('unknown embedded metadata comes from the host theme', () {
      final tokenizer = MonarchTokenizer(
        'test',
        compile('test', _embeddedGrammar()),
        tokenTheme: theme,
      );
      final result = tokenizer.tokenizeEncoded(
        '<xy>',
        true,
        tokenizer.getInitialState(),
      );
      expect(result.tokens, [0, 0xff010402, 1, 0xff008403, 3, 0xff010402]);
    });
  });
}
