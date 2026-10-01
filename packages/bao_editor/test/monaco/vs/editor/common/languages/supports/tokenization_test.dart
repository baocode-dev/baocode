/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../../../../../lib/ide/editor/monaco/LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Source-derived checks for VS Code tokenization.ts and tokenization.test.ts
// at 6a598d4a13031703d483d103c1d934a36ad27971.

import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/editor/monaco/vs/editor/common/encoded_token_attributes.dart';
import 'package:baocode/ide/editor/monaco/vs/editor/common/languages/supports/tokenization.dart';

void expectRule(
  ThemeTrieElementRule actual,
  int fontStyle,
  int foreground,
  int background,
) {
  expect(TokenMetadata.getFontStyle(actual.metadata), fontStyle);
  expect(TokenMetadata.getForeground(actual.metadata), foreground);
  expect(TokenMetadata.getBackground(actual.metadata), background);
  expect(
    actual.metadata,
    (fontStyle << 11) | (foreground << 15) | (background << 24),
  );
}

void main() {
  group('Token theme parsing', () {
    test(
      'preserves index, raw colors, unset/empty and combined font styles',
      () {
        final parsed = parseTokenTheme([
          const TokenThemeRule(
            token: '',
            foreground: 'F8F8F2',
            background: '272822',
          ),
          const TokenThemeRule(token: 'source', background: '100000'),
          const TokenThemeRule(token: 'bar', fontStyle: 'bold'),
          const TokenThemeRule(
            token: 'constant',
            fontStyle: 'italic',
            foreground: 'ff0000',
          ),
          const TokenThemeRule(token: 'constant.numeric', foreground: '00ff00'),
          const TokenThemeRule(
            token: 'constant.numeric.hex',
            fontStyle: 'bold',
          ),
          const TokenThemeRule(
            token: 'constant.numeric.oct',
            fontStyle: 'bold italic underline',
          ),
          const TokenThemeRule(
            token: 'constant.numeric.bin',
            fontStyle: 'bold strikethrough',
          ),
          const TokenThemeRule(
            token: 'constant.numeric.dec',
            fontStyle: '',
            foreground: '0000ff',
          ),
          const TokenThemeRule(token: 'unknown', fontStyle: 'unknown\titalic'),
        ]);
        expect(
          parsed
              .map(
                (rule) => [
                  rule.token,
                  rule.index,
                  rule.fontStyle,
                  rule.foreground,
                  rule.background,
                ],
              )
              .toList(),
          [
            ['', 0, FontStyle.notSet, 'F8F8F2', '272822'],
            ['source', 1, FontStyle.notSet, null, '100000'],
            ['bar', 2, FontStyle.bold, null, null],
            ['constant', 3, FontStyle.italic, 'ff0000', null],
            ['constant.numeric', 4, FontStyle.notSet, '00ff00', null],
            ['constant.numeric.hex', 5, FontStyle.bold, null, null],
            [
              'constant.numeric.oct',
              6,
              FontStyle.bold | FontStyle.italic | FontStyle.underline,
              null,
              null,
            ],
            [
              'constant.numeric.bin',
              7,
              FontStyle.bold | FontStyle.strikethrough,
              null,
              null,
            ],
            ['constant.numeric.dec', 8, FontStyle.none, '0000ff', null],
            ['unknown', 9, FontStyle.none, null, null],
          ],
        );
      },
    );
  });

  group('Token theme matching', () {
    test('deeper scopes win even if supplied before their parents', () {
      final theme = TokenTheme.createFromRawTokenTheme([
        const TokenThemeRule(
          token: '',
          foreground: '100000',
          background: '200000',
        ),
        const TokenThemeRule(
          token: 'punctuation.definition.string.begin.html',
          foreground: '300000',
        ),
        const TokenThemeRule(
          token: 'punctuation.definition.string',
          foreground: '400000',
        ),
      ], []);
      expectRule(
        theme.matchRule('punctuation.definition.string.begin.html'),
        0,
        4,
        2,
      );
      expectRule(
        theme.matchRule('punctuation.definition.string.begin.css'),
        0,
        3,
        2,
      );
    });

    test('inherits styles, colors, and scope boundaries from upstream matching fixture', () {
      final theme = TokenTheme.createFromRawTokenTheme([
        const TokenThemeRule(
          token: '',
          foreground: 'F8F8F2',
          background: '272822',
        ),
        const TokenThemeRule(token: 'source', background: '100000'),
        const TokenThemeRule(token: 'something', background: '100000'),
        const TokenThemeRule(token: 'bar', background: '200000'),
        const TokenThemeRule(token: 'baz', background: '200000'),
        const TokenThemeRule(token: 'bar', fontStyle: 'bold'),
        const TokenThemeRule(
          token: 'constant',
          fontStyle: 'italic',
          foreground: '300000',
        ),
        const TokenThemeRule(token: 'constant.numeric', foreground: '400000'),
        const TokenThemeRule(token: 'constant.numeric.hex', fontStyle: 'bold'),
        const TokenThemeRule(
          token: 'constant.numeric.oct',
          fontStyle: 'bold italic underline',
        ),
        const TokenThemeRule(
          token: 'constant.numeric.bin',
          fontStyle: 'bold strikethrough',
        ),
        const TokenThemeRule(
          token: 'constant.numeric.dec',
          fontStyle: '',
          foreground: '500000',
        ),
        const TokenThemeRule(
          token: 'storage.object.bar',
          fontStyle: '',
          foreground: '600000',
        ),
      ], []);
      final colors = ColorMap();
      final a = colors.getId('F8F8F2');
      final b = colors.getId('272822');
      final c = colors.getId('200000');
      final d = colors.getId('300000');
      final e = colors.getId('400000');
      final f = colors.getId('500000');
      final g = colors.getId('100000');
      final h = colors.getId('600000');
      for (final scope in [
        '',
        'bazz',
        'asdfg',
        'storage.object',
        'storage.object.bart',
      ]) {
        expectRule(theme.matchRule(scope), FontStyle.none, a, b);
      }
      for (final scope in ['source', 'source.ts', 'something.tss']) {
        expectRule(theme.matchRule(scope), FontStyle.none, a, g);
      }
      expectRule(theme.matchRule('baz.ts'), FontStyle.none, a, c);
      expectRule(theme.matchRule('bar.x'), FontStyle.bold, a, c);
      expectRule(theme.matchRule('constant.string'), FontStyle.italic, d, b);
      expectRule(
        theme.matchRule('constant.numeric.baz'),
        FontStyle.italic,
        e,
        b,
      );
      expectRule(
        theme.matchRule('constant.numeric.hex.baz'),
        FontStyle.bold,
        e,
        b,
      );
      expectRule(
        theme.matchRule('constant.numeric.oct.baz'),
        FontStyle.bold | FontStyle.italic | FontStyle.underline,
        e,
        b,
      );
      expectRule(
        theme.matchRule('constant.numeric.bin'),
        FontStyle.bold | FontStyle.strikethrough,
        e,
        b,
      );
      expectRule(
        theme.matchRule('constant.numeric.dec.baz'),
        FontStyle.none,
        f,
        b,
      );
      expectRule(
        theme.matchRule('storage.object.bar.baz'),
        FontStyle.none,
        h,
        b,
      );
      expect(theme.getColorMap(), colors.getColorMap());
    });

    test('unknown intermediate scopes inherit the nearest ancestor', () {
      final theme = TokenTheme.createFromRawTokenTheme([
        const TokenThemeRule(token: 'storage.object.bar', foreground: 'ABCDEF'),
      ], []);
      final root = theme.getThemeTrieElement();
      expect(root.children.keys, ['storage']);
      final storage = root.children['storage']!;
      final object = storage.children['object']!;
      expectRule(storage.mainRule, FontStyle.none, 1, 2);
      expectRule(object.mainRule, FontStyle.none, 1, 2);
      expectRule(object.children['bar']!.mainRule, FontStyle.none, 3, 2);
      expectRule(theme.matchRule('storage.object.bart'), FontStyle.none, 1, 2);
    });
  });

  group('Token theme resolving', () {
    test('strcmp sorts lexicographically', () {
      expect(['bar', 'z', 'zu', 'a', 'ab', '']..sort(strcmp), [
        '',
        'a',
        'ab',
        'bar',
        'z',
        'zu',
      ]);
    });

    test('supplies upstream black-on-white defaults', () {
      final theme = TokenTheme.createFromParsedTokenTheme([], []);
      expect(theme.getColorMap(), [
        null,
        const Color(0xff000000),
        const Color(0xffffffff),
      ]);
      final root = theme.getThemeTrieElement();
      expectRule(root.mainRule, FontStyle.none, 1, 2);
      expect(root.children, isEmpty);
    });

    test('upstream incoming-default variants preserve unspecified fields', () {
      for (final (rule, expectedStyle, expectedColors)
          in <(ParsedTokenThemeRule, int, List<Color?>)>[
            (
              const ParsedTokenThemeRule('', -1, FontStyle.notSet, null, null),
              FontStyle.none,
              [null, const Color(0xff000000), const Color(0xffffffff)],
            ),
            (
              const ParsedTokenThemeRule('', -1, FontStyle.none, null, null),
              FontStyle.none,
              [null, const Color(0xff000000), const Color(0xffffffff)],
            ),
            (
              const ParsedTokenThemeRule('', -1, FontStyle.bold, null, null),
              FontStyle.bold,
              [null, const Color(0xff000000), const Color(0xffffffff)],
            ),
            (
              const ParsedTokenThemeRule(
                '',
                -1,
                FontStyle.notSet,
                'ff0000',
                null,
              ),
              FontStyle.none,
              [null, const Color(0xffff0000), const Color(0xffffffff)],
            ),
            (
              const ParsedTokenThemeRule(
                '',
                -1,
                FontStyle.notSet,
                null,
                'ff0000',
              ),
              FontStyle.none,
              [null, const Color(0xff000000), const Color(0xffff0000)],
            ),
          ]) {
        final theme = TokenTheme.createFromParsedTokenTheme([rule], []);
        expect(theme.getColorMap(), expectedColors);
        expectRule(theme.matchRule(''), expectedStyle, 1, 2);
      }
    });

    test(
      'merges default rules in order, leaving unspecified fields unchanged',
      () {
        final theme = TokenTheme.createFromParsedTokenTheme([
          const ParsedTokenThemeRule('', -1, FontStyle.notSet, null, 'ff0000'),
          const ParsedTokenThemeRule('', 0, FontStyle.notSet, '00ff00', null),
          const ParsedTokenThemeRule('', 1, FontStyle.bold, null, null),
          const ParsedTokenThemeRule(
            'var',
            2,
            FontStyle.notSet,
            'aaaaaa',
            null,
          ),
        ], []);
        expectRule(theme.matchRule(''), FontStyle.bold, 1, 2);
        expectRule(theme.matchRule('var.identifier'), FontStyle.bold, 3, 2);
        expect(theme.getColorMap(), [
          null,
          const Color(0xff00ff00),
          const Color(0xffff0000),
          const Color(0xffaaaaaa),
        ]);
      },
    );

    test(
      'equal-scope source index controls merging, parent styles are inherited',
      () {
        final theme = TokenTheme.createFromParsedTokenTheme([
          const ParsedTokenThemeRule(
            '',
            -1,
            FontStyle.notSet,
            'F8F8F2',
            '272822',
          ),
          const ParsedTokenThemeRule('var', 1, FontStyle.bold, null, null),
          const ParsedTokenThemeRule(
            'var',
            0,
            FontStyle.notSet,
            'ff0000',
            null,
          ),
          const ParsedTokenThemeRule(
            'var.identifier',
            2,
            FontStyle.notSet,
            '00ff00',
            null,
          ),
        ], []);
        final root = theme.getThemeTrieElement();
        expectRule(root.mainRule, FontStyle.none, 1, 2);
        final variable = root.children['var']!;
        expectRule(variable.mainRule, FontStyle.bold, 3, 2);
        expectRule(
          variable.children['identifier']!.mainRule,
          FontStyle.bold,
          4,
          2,
        );
        expectRule(
          theme.matchRule('var.identifier.more'),
          FontStyle.bold,
          4,
          2,
        );
      },
    );

    test('custom token colors reserve IDs before defaults and rules', () {
      final theme = TokenTheme.createFromParsedTokenTheme(
        [
          const ParsedTokenThemeRule(
            'var',
            -1,
            FontStyle.notSet,
            'F8F8F2',
            null,
          ),
        ],
        ['000000', 'FFFFFF', '0F0F0F'],
      );
      expect(theme.getColorMap(), [
        null,
        const Color(0xff000000),
        const Color(0xffffffff),
        const Color(0xff0f0f0f),
        const Color(0xfff8f8f2),
      ]);
      expectRule(theme.matchRule('var'), FontStyle.none, 4, 2);
    });
  });

  group('ColorMap', () {
    test('normalizes case/hash, discards alpha, and returns a copy', () {
      final map = ColorMap();
      expect(map.getId(null), 0);
      expect(map.getId('#abc12380'), 1);
      expect(map.getId('ABC123'), 1);
      expect(map.getId('#000000'), 2);
      final snapshot = map.getColorMap();
      expect(snapshot, [
        null,
        const Color(0xffabc123),
        const Color(0xff000000),
      ]);
      snapshot.add(const Color(0xffffffff));
      expect(map.getColorMap().length, 3);
      for (final invalid in [
        '',
        'red',
        '#fff',
        '#aabbccddeeff',
        'gg0000',
        ' 000000',
      ]) {
        expect(() => map.getId(invalid), throwsFormatException);
      }
    });
  });

  group('Metadata matching', () {
    test('detects embedded standard token types at word boundaries', () {
      for (final pair in <(String, int)>[
        ('comment', StandardTokenType.comment),
        ('source.comment.block', StandardTokenType.comment),
        ('string.quoted', StandardTokenType.string),
        ('regex', StandardTokenType.regEx),
        ('regexp', StandardTokenType.regEx),
        ('name_regexp', StandardTokenType.other),
        ('commentary', StandardTokenType.other),
        ('COMMENT', StandardTokenType.other),
        ('other', StandardTokenType.other),
        ('string.comment', StandardTokenType.string),
      ]) {
        expect(toStandardTokenType(pair.$1), pair.$2, reason: pair.$1);
      }
    });

    test('caches language-independent metadata across language IDs', () {
      final rules = <TokenThemeRule>[
        const TokenThemeRule(
          token: '',
          foreground: '101010',
          background: '202020',
          fontStyle: 'bold',
        ),
        const TokenThemeRule(
          token: 'comment',
          foreground: 'ffffff',
          fontStyle: 'italic',
        ),
      ];
      final theme = TokenTheme.createFromRawTokenTheme(rules, []);
      final first = theme.match(3, 'comment.line');
      final second = theme.match(210, 'comment.line');
      expect(TokenMetadata.getLanguageId(first), 3);
      expect(TokenMetadata.getLanguageId(second), 210);
      expect(
        first & ~MetadataConsts.languageIdMask,
        second & ~MetadataConsts.languageIdMask,
      );
      expect(TokenMetadata.getTokenType(second), StandardTokenType.comment);
      expect(TokenMetadata.getFontStyle(second), FontStyle.italic);
      expect(TokenMetadata.getForeground(second), 3);
      expect(TokenMetadata.getBackground(second), 2);
      expect(
        TokenMetadata.getTokenType(theme.match(255, 'plain')),
        StandardTokenType.other,
      );
      expect(theme.match(255, 'plain'), lessThanOrEqualTo(0xffffffff));
    });

    test('encodes backgrounds above 127 as unsigned 32-bit metadata', () {
      final customColors = List.generate(
        128,
        (i) => i.toRadixString(16).padLeft(6, '0'),
      );
      final theme = TokenTheme.createFromRawTokenTheme([], customColors);
      final metadata = theme.match(42, 'other');
      expect(TokenMetadata.getForeground(metadata), 1);
      expect(TokenMetadata.getBackground(metadata), 129);
      expect(TokenMetadata.getLanguageId(metadata), 42);
      expect(metadata, (129 << 24) | (1 << 15) | 42);
      expect(metadata, lessThanOrEqualTo(0xffffffff));
    });
  });

  group('CSS helpers', () {
    test(
      'uses actual token map colors, including monochrome and font flags',
      () {
        final map = ColorMap();
        map.getId('#000000');
        map.getId('00ABCD80');
        expect(
          generateTokensCSSForColorMap(map.getColorMap()),
          [
            '',
            '.mtk1 { color: #000000; }',
            '.mtk2 { color: #00abcd; }',
            '.mtki { font-style: italic; }',
            '.mtkb { font-weight: bold; }',
            '.mtku { text-decoration: underline; text-underline-position: under; }',
            '.mtks { text-decoration: line-through; }',
            '.mtks.mtku { text-decoration: underline line-through; text-underline-position: under; }',
          ].join('\n'),
        );
      },
    );

    test('CSS formats nonopaque colors as upstream RGBA', () {
      final css = generateTokensCSSForColorMap([
        null,
        const Color(0x80112233),
        const Color(0x00112233),
      ]);
      expect(css, contains('.mtk1 { color: rgba(17, 34, 51, 0.5); }'));
      expect(css, contains('.mtk2 { color: rgba(17, 34, 51, 0); }'));
    });

    test(
      'deduplicates font classes and omits unset and line-height-only options',
      () {
        expect(
          classNameForFontTokenDecorations('  Fira Code!  ', 1.0),
          'font-decoration-fira-code--1',
        );
        expect(
          classNameForFontTokenDecorations('', 0),
          'font-decoration-default-0',
        );
        expect(
          generateTokensCSSForFontMap([
            null,
            const FontTokenOptions(lineHeightMultiplier: 1.5),
            const FontTokenOptions(
              fontFamily: 'Fira Code',
              fontSizeMultiplier: 1.25,
            ),
            const FontTokenOptions(
              fontFamily: 'Fira Code',
              fontSizeMultiplier: 1.25,
            ),
            const FontTokenOptions(fontSizeMultiplier: 2),
          ]),
          [
            '.font-decoration-fira-code-1-25 {font-family: Fira Code;font-size: calc(var(--editor-font-size)*1.25);}',
            '.font-decoration-default-2 {font-size: calc(var(--editor-font-size)*2);}',
          ].join('\n'),
        );
      },
    );
  });
}
