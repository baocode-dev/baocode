// Adapted from vscode-textmate 9.3.2 (25b68dad…): src/tests/grammar.test.ts
// (MIT, see fixtures/LICENSE.md).

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/textmate/vscode_textmate/grammar/grammar.dart';
import 'package:bao_editor/textmate/vscode_textmate/main.dart';

import 'support/onig.dart';

void assertEquals(
  int metadata,
  int languageId,
  int tokenType,
  bool containsBalancedBrackets,
  int fontStyle,
  int foreground,
  int background,
) {
  final actual = {
    'languageId': EncodedTokenAttributes.getLanguageId(metadata),
    'tokenType': EncodedTokenAttributes.getTokenType(metadata),
    'containsBalancedBrackets': EncodedTokenAttributes.containsBalancedBrackets(
      metadata,
    ),
    'fontStyle': EncodedTokenAttributes.getFontStyle(metadata),
    'foreground': EncodedTokenAttributes.getForeground(metadata),
    'background': EncodedTokenAttributes.getBackground(metadata),
  };

  final expected = {
    'languageId': languageId,
    'tokenType': tokenType,
    'containsBalancedBrackets': containsBalancedBrackets,
    'fontStyle': fontStyle,
    'foreground': foreground,
    'background': background,
  };

  expect(
    actual,
    expected,
    reason: 'equals for ${EncodedTokenAttributes.toBinaryStr(metadata)}',
  );
}

Map<String, Object?> _font(IFontInfo f) => {
  'startIndex': f.startIndex,
  'endIndex': f.endIndex,
  'fontFamily': f.fontFamily,
  'fontSizeMultiplier': f.fontSizeMultiplier,
  'lineHeightMultiplier': f.lineHeightMultiplier,
};

void main() {
  test('StackElementMetadata works', () {
    final value = EncodedTokenAttributes.set(
      0,
      1,
      OptionalStandardTokenType.regEx,
      false,
      FontStyle.underline | FontStyle.bold,
      101,
      102,
    );
    assertEquals(
      value,
      1,
      StandardTokenType.regEx,
      false,
      FontStyle.underline | FontStyle.bold,
      101,
      102,
    );
  });

  test('StackElementMetadata can overwrite languageId', () {
    var value = EncodedTokenAttributes.set(
      0,
      1,
      OptionalStandardTokenType.regEx,
      false,
      FontStyle.underline | FontStyle.bold,
      101,
      102,
    );
    assertEquals(
      value,
      1,
      StandardTokenType.regEx,
      false,
      FontStyle.underline | FontStyle.bold,
      101,
      102,
    );

    value = EncodedTokenAttributes.set(
      value,
      2,
      OptionalStandardTokenType.notSet,
      false,
      FontStyle.notSet,
      0,
      0,
    );
    assertEquals(
      value,
      2,
      StandardTokenType.regEx,
      false,
      FontStyle.underline | FontStyle.bold,
      101,
      102,
    );
  });

  test('StackElementMetadata can overwrite tokenType', () {
    var value = EncodedTokenAttributes.set(
      0,
      1,
      OptionalStandardTokenType.regEx,
      false,
      FontStyle.underline | FontStyle.bold,
      101,
      102,
    );
    assertEquals(
      value,
      1,
      StandardTokenType.regEx,
      false,
      FontStyle.underline | FontStyle.bold,
      101,
      102,
    );

    value = EncodedTokenAttributes.set(
      value,
      0,
      OptionalStandardTokenType.comment,
      false,
      FontStyle.notSet,
      0,
      0,
    );
    assertEquals(
      value,
      1,
      StandardTokenType.comment,
      false,
      FontStyle.underline | FontStyle.bold,
      101,
      102,
    );
  });

  test('StackElementMetadata can overwrite font style', () {
    var value = EncodedTokenAttributes.set(
      0,
      1,
      OptionalStandardTokenType.regEx,
      false,
      FontStyle.underline | FontStyle.bold,
      101,
      102,
    );
    assertEquals(
      value,
      1,
      StandardTokenType.regEx,
      false,
      FontStyle.underline | FontStyle.bold,
      101,
      102,
    );

    value = EncodedTokenAttributes.set(
      value,
      0,
      OptionalStandardTokenType.notSet,
      false,
      FontStyle.none,
      0,
      0,
    );
    assertEquals(
      value,
      1,
      StandardTokenType.regEx,
      false,
      FontStyle.none,
      101,
      102,
    );
  });

  test('StackElementMetadata can overwrite font style with strikethrough', () {
    var value = EncodedTokenAttributes.set(
      0,
      1,
      OptionalStandardTokenType.regEx,
      false,
      FontStyle.strikethrough,
      101,
      102,
    );
    assertEquals(
      value,
      1,
      StandardTokenType.regEx,
      false,
      FontStyle.strikethrough,
      101,
      102,
    );

    value = EncodedTokenAttributes.set(
      value,
      0,
      OptionalStandardTokenType.notSet,
      false,
      FontStyle.none,
      0,
      0,
    );
    assertEquals(
      value,
      1,
      StandardTokenType.regEx,
      false,
      FontStyle.none,
      101,
      102,
    );
  });

  test('StackElementMetadata can overwrite foreground', () {
    var value = EncodedTokenAttributes.set(
      0,
      1,
      OptionalStandardTokenType.regEx,
      false,
      FontStyle.underline | FontStyle.bold,
      101,
      102,
    );
    assertEquals(
      value,
      1,
      StandardTokenType.regEx,
      false,
      FontStyle.underline | FontStyle.bold,
      101,
      102,
    );

    value = EncodedTokenAttributes.set(
      value,
      0,
      OptionalStandardTokenType.notSet,
      false,
      FontStyle.notSet,
      5,
      0,
    );
    assertEquals(
      value,
      1,
      StandardTokenType.regEx,
      false,
      FontStyle.underline | FontStyle.bold,
      5,
      102,
    );
  });

  test('StackElementMetadata can overwrite background', () {
    var value = EncodedTokenAttributes.set(
      0,
      1,
      OptionalStandardTokenType.regEx,
      false,
      FontStyle.underline | FontStyle.bold,
      101,
      102,
    );
    assertEquals(
      value,
      1,
      StandardTokenType.regEx,
      false,
      FontStyle.underline | FontStyle.bold,
      101,
      102,
    );

    value = EncodedTokenAttributes.set(
      value,
      0,
      OptionalStandardTokenType.notSet,
      false,
      FontStyle.notSet,
      0,
      7,
    );
    assertEquals(
      value,
      1,
      StandardTokenType.regEx,
      false,
      FontStyle.underline | FontStyle.bold,
      101,
      7,
    );
  });

  test('StackElementMetadata can overwrite balanced backet bit', () {
    var value = EncodedTokenAttributes.set(
      0,
      1,
      OptionalStandardTokenType.regEx,
      false,
      FontStyle.underline | FontStyle.bold,
      101,
      102,
    );
    assertEquals(
      value,
      1,
      StandardTokenType.regEx,
      false,
      FontStyle.underline | FontStyle.bold,
      101,
      102,
    );

    value = EncodedTokenAttributes.set(
      value,
      0,
      OptionalStandardTokenType.notSet,
      true,
      FontStyle.notSet,
      0,
      0,
    );
    assertEquals(
      value,
      1,
      StandardTokenType.regEx,
      true,
      FontStyle.underline | FontStyle.bold,
      101,
      102,
    );

    value = EncodedTokenAttributes.set(
      value,
      0,
      OptionalStandardTokenType.notSet,
      false,
      FontStyle.notSet,
      0,
      0,
    );
    assertEquals(
      value,
      1,
      StandardTokenType.regEx,
      false,
      FontStyle.underline | FontStyle.bold,
      101,
      102,
    );
  });

  test('StackElementMetadata can work at max values', () {
    const maxLangId = 255;
    const maxTokenType =
        StandardTokenType.comment |
        StandardTokenType.other |
        StandardTokenType.regEx |
        StandardTokenType.string;
    const maxFontStyle =
        FontStyle.bold | FontStyle.italic | FontStyle.underline;
    const maxForeground = 511;
    const maxBackground = 254;

    final value = EncodedTokenAttributes.set(
      0,
      maxLangId,
      maxTokenType,
      true,
      maxFontStyle,
      maxForeground,
      maxBackground,
    );
    assertEquals(
      value,
      maxLangId,
      maxTokenType,
      true,
      maxFontStyle,
      maxForeground,
      maxBackground,
    );
  });

  test('Shadowed rules are resolved correctly', () async {
    final registry = Registry(
      RegistryOptions(loadGrammar: (_) async => null, onigLib: testOnigLib()),
    );
    try {
      final grammar = await registry.addGrammar(
        IRawGrammar({
          'scopeName': 'source.test',
          'repository': {
            r'$base': null,
            r'$self': null,
            'foo': {'include': '#bar'},
            'bar': {'match': 'bar1', 'name': 'outer'},
          },
          'patterns': [
            {
              'patterns': [
                {'include': '#foo'},
              ],
              'repository': {
                r'$base': null,
                r'$self': null,
                'bar': {'match': 'bar1', 'name': 'inner'},
              },
            },
            // When you move this up, the test passes
            {
              'begin': 'begin',
              'patterns': [
                {'include': '#foo'},
              ],
              'end': 'end',
            },
          ],
        }),
      );
      final result = grammar.tokenizeLine('bar1', null);
      // TODO this should be inner!
      expect(
        [
          for (final t in result.tokens)
            {
              'startIndex': t.startIndex,
              'endIndex': t.endIndex,
              'scopes': t.scopes,
            },
        ],
        [
          {
            'startIndex': 0,
            'endIndex': 4,
            'scopes': ['source.test', 'outer'],
          },
        ],
      );
    } finally {
      registry.dispose();
    }
  }, skip: 'skipped upstream (test.skip)');

  test('Fonts are correctly set', () async {
    final registry = Registry(
      RegistryOptions(loadGrammar: (_) async => null, onigLib: testOnigLib()),
    );
    try {
      registry.setTheme(
        const IRawTheme(
          settings: [
            IRawThemeSetting(
              scope: 'bar.test',
              settings: IRawThemeSettingStyleWithFont(
                fontFamily: 'monospace',
                fontSize: 1.2,
                lineHeight: 3,
              ),
            ),
          ],
        ),
      );
      final grammar = await registry.addGrammar(
        IRawGrammar({
          'scopeName': 'source.test',
          'repository': {r'$self': null, r'$base': null},
          'patterns': [
            {'match': r'\bbar\b', 'name': 'bar.test'},
          ],
        }),
      );
      final result = grammar.tokenizeLine2('bar hello', null);
      expect(result.fonts.map(_font).toList(), [
        _font(FontInfo(0, 3, 'monospace', 1.2, 3)),
      ]);
    } finally {
      registry.dispose();
    }
  });

  test('Fonts are correctly set 2', () async {
    final registry = Registry(
      RegistryOptions(loadGrammar: (_) async => null, onigLib: testOnigLib()),
    );
    try {
      registry.setTheme(
        const IRawTheme(
          settings: [
            IRawThemeSetting(
              scope: 'entity.name.function.ts',
              settings: IRawThemeSettingStyleWithFont(
                fontFamily: 'Times New Roman',
                fontSize: 1.3,
                lineHeight: 3,
              ),
            ),
          ],
        ),
      );
      final grammar = await registry.addGrammar(
        IRawGrammar({
          'scopeName': 'source.ts',
          'repository': {r'$self': null, r'$base': null},
          'patterns': [
            {'match': 'g', 'name': 'entity.name.function.ts'},
          ],
        }),
      );
      final result = grammar.tokenizeLine2('function g() {}', null);
      expect(result.fonts.map(_font).toList(), [
        _font(FontInfo(9, 10, 'Times New Roman', 1.3, 3)),
      ]);
    } finally {
      registry.dispose();
    }
  });
}
