// Adapted from vscode-textmate 9.3.2 (25b68dad…): src/tests/themes.test.ts,
// src/tests/themeTest.ts and src/tests/themedTokenizer.ts (MIT, see
// fixtures/LICENSE.md).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/textmate/vscode_textmate/main.dart';
import 'package:bao_editor/textmate/vscode_textmate/theme.dart';
import 'package:bao_editor/textmate/vscode_textmate/utils.dart';

import 'support/fixtures.dart';
import 'support/onig.dart';
import 'support/resolver.dart';

const String themesTestPath = 'themes';

class ThemeData {
  ThemeData(this.themeName, this.theme, this.registry);

  final String themeName;
  final IRawTheme theme;
  final Registry registry;
}

class ThemeInfo {
  const ThemeInfo(this._themeName, this._filename, [this._includeFilename]);

  final String _themeName;
  final String _filename;
  final String? _includeFilename;

  static Map<String, Object?> _loadThemeFile(String filename) {
    return (loadThemeFile('$themesTestPath/$filename')! as Map)
        .cast<String, Object?>();
  }

  ThemeData create(Resolver resolver) {
    final theme = Map<String, Object?>.of(_loadThemeFile(_filename));
    final includeFilename = _includeFilename;
    if (includeFilename != null) {
      final includeTheme = _loadThemeFile(includeFilename);
      theme['settings'] = [
        ...(includeTheme['settings']! as List),
        ...(theme['settings']! as List),
      ];
    }

    final rawTheme = rawThemeFromJson(theme);
    final registry = Registry(resolver.options);
    registry.setTheme(rawTheme);

    return ThemeData(_themeName, rawTheme, registry);
  }
}

const List<ThemeInfo> _themes = [
  ThemeInfo('abyss', 'Abyss.tmTheme'),
  ThemeInfo('dark_vs', 'dark_vs.json'),
  ThemeInfo('light_vs', 'light_vs.json'),
  ThemeInfo('hc_black', 'hc_black.json'),
  ThemeInfo('dark_plus', 'dark_plus.json', 'dark_vs.json'),
  ThemeInfo('light_plus', 'light_plus.json', 'light_vs.json'),
  ThemeInfo('kimbie_dark', 'Kimbie_dark.tmTheme'),
  ThemeInfo('monokai', 'Monokai.tmTheme'),
  ThemeInfo('monokai_dimmed', 'dimmed-monokai.tmTheme'),
  ThemeInfo('quietlight', 'QuietLight.tmTheme'),
  ThemeInfo('red', 'red.tmTheme'),
  ThemeInfo('solarized_dark', 'Solarized-dark.tmTheme'),
  ThemeInfo('solarized_light', 'Solarized-light.tmTheme'),
  ThemeInfo('tomorrow_night_blue', 'Tomorrow-Night-Blue.tmTheme'),
];

Resolver _createResolver() {
  final grammars = [
    for (final g
        in jsonDecode(readFixture('$themesTestPath/grammars.json')) as List)
      IGrammarRegistration.fromJson(
        (g as Map).cast<String, Object?>(),
        fixturePath(themesTestPath),
      ),
  ];
  final languages = [
    for (final l
        in jsonDecode(readFixture('$themesTestPath/languages.json')) as List)
      ILanguageRegistration.fromJson((l as Map).cast<String, Object?>()),
  ];
  return Resolver(grammars, languages, testOnigLib());
}

/// `IThemedToken`, as upstream's `JSON.stringify` writes it: `color` is
/// omitted when the color map has no entry for the id.
List<Map<String, Object?>> tokenizeWithTheme(
  List<String> colorMap,
  String fileContents,
  IGrammar grammar,
) {
  final lines = splitLines(fileContents);

  StateStack? ruleStack;
  final actual = <Map<String, Object?>>[];

  for (var i = 0, len = lines.length; i < len; i++) {
    final line = lines[i];
    final result = grammar.tokenizeLine2(line, ruleStack);
    final tokensLength = result.tokens.length ~/ 2;
    for (var j = 0; j < tokensLength; j++) {
      final startIndex = result.tokens[2 * j];
      final nextStartIndex = j + 1 < tokensLength
          ? result.tokens[2 * j + 2]
          : line.length;
      final tokenText = line.substring(startIndex, nextStartIndex);
      if (tokenText == '') {
        continue;
      }
      final metadata = result.tokens[2 * j + 1];
      final foreground = EncodedTokenAttributes.getForeground(metadata);
      final token = <String, Object?>{'content': tokenText};
      // `getColorMap` fills the hole at index 0 with ''; upstream reads
      // undefined there, which `JSON.stringify` omits.
      final color = foreground < colorMap.length ? colorMap[foreground] : '';
      if (color.isNotEmpty) {
        token['color'] = color;
      }
      actual.add(token);
    }

    if (ruleStack != null) {
      final diff = diffStateStacksRefEq(ruleStack, result.ruleStack);
      ruleStack = applyStateStackDiff(ruleStack, diff);
    } else {
      ruleStack = result.ruleStack;
    }
  }

  return actual;
}

class ThemeTest {
  ThemeTest(String testFile, List<ThemeData> themeDatas, Resolver resolver)
    : testName = testFile {
    final testFilePath = '$themesTestPath/tests/$testFile';
    final testFileContents = readFixture(testFilePath);

    expected = jsonDecode(readFixture('$testFilePath.result'));

    // Determine the language
    final language =
        resolver.findLanguageByExtension(extname(testFile)) ??
        resolver.findLanguageByFilename(testFile);
    if (language == null) {
      throw StateError('Could not determine language for $testFile');
    }
    final grammar = resolver.findGrammarByLanguage(language);

    // Upstream stores `undefined` for unknown languages, which the scope
    // attribute provider reads as language 0.
    final embeddedLanguages = <String, int>{};
    final grammarEmbeddedLanguages = grammar.embeddedLanguages;
    if (grammarEmbeddedLanguages != null) {
      for (final entry in grammarEmbeddedLanguages.entries) {
        embeddedLanguages[entry.key] = resolver.language2id[entry.value] ?? 0;
      }
    }

    for (final themeData in themeDatas) {
      _tests.add(
        _SingleThemeTest(
          themeData,
          testFileContents,
          grammar.scopeName,
          resolver.language2id[language]!,
          embeddedLanguages,
        ),
      );
    }
  }

  final List<_SingleThemeTest> _tests = <_SingleThemeTest>[];
  late final Object? expected;
  final String testName;
  Object? actual;

  Future<void> evaluate() async {
    await Future.wait(_tests.map((t) => t.evaluate()));

    final result = <String, Object?>{};
    for (final t in _tests) {
      result[t.themeData.themeName] = t.actual;
    }
    actual = result;
  }
}

class _SingleThemeTest {
  _SingleThemeTest(
    this.themeData,
    this.contents,
    this.initialScopeName,
    this.initialLanguage,
    this.embeddedLanguages,
  );

  final ThemeData themeData;
  final String contents;
  final String initialScopeName;
  final int initialLanguage;
  final IEmbeddedLanguagesMap embeddedLanguages;

  List<Map<String, Object?>>? actual;

  Future<void> evaluate() async {
    final grammar = await themeData.registry.loadGrammarWithEmbeddedLanguages(
      initialScopeName,
      initialLanguage,
      embeddedLanguages,
    );
    if (grammar == null) {
      throw StateError('Cannot load grammar for $initialScopeName');
    }
    actual = tokenizeWithTheme(
      themeData.registry.getColorMap(),
      contents,
      grammar,
    );
  }
}

Future<void> testTokenizationTime(String file) async {
  // Load dark_vs theme
  final theme = rawThemeFromJson(loadThemeFile('$themesTestPath/dark_vs.json'));

  final resolver = _createResolver();
  final registry = Registry(resolver.options);
  registry.setTheme(theme);

  // Load TypeScript grammar
  final tsGrammar = await registry.loadGrammar('source.ts');
  expect(tsGrammar, isNotNull, reason: 'TypeScript grammar should be loaded');

  // Read test.ts file
  final testFileContent = readFixture('$themesTestPath/fixtures/$file');
  final lines = splitLines(testFileContent);

  // Tokenize all lines
  List<Map<String, Object?>> tokenizeLines() {
    StateStack? ruleStack;
    final tokenizedLines = <Map<String, Object?>>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final result = tsGrammar!.tokenizeLine2(line, ruleStack);
      ruleStack = result.ruleStack;
      tokenizedLines.add({
        'line': i + 1,
        'tokens': result.tokens,
        'fonts': result.fonts,
      });
    }
    return tokenizedLines;
  }

  // Verify we tokenized all lines
  final stopwatch = Stopwatch()..start();
  tokenizeLines();
  stopwatch.stop();

  printOnFailure('Tokenization time: ${stopwatch.elapsedMilliseconds}');
}

List<Object?> _rule(ParsedThemeRule r) => [
  r.scope,
  r.parentScopes,
  r.index,
  r.fontStyle,
  r.foreground,
  r.background,
  r.fontFamily,
  r.fontSize,
  r.lineHeight,
];

List<List<Object?>> _rules(List<ParsedThemeRule> rules) =>
    rules.map(_rule).toList();

/// Upstream compares `_colorMap`, and `_defaults`/`_root` of `actual` with
/// themselves, so only the color map is checked.
void assertThemeEqual(Theme actual, Theme expected) {
  expect(actual.getColorMap(), expected.getColorMap());
}

IRawThemeSetting _setting(
  Object? scope, {
  String? name,
  Object? fontStyle,
  Object? foreground,
  Object? background,
}) => IRawThemeSetting(
  name: name,
  scope: scope,
  settings: IRawThemeSettingStyle(
    fontStyle: fontStyle,
    foreground: foreground,
    background: background,
  ),
);

void main() {
  group('themes', () {
    final resolver = _createResolver();
    final themeData = [for (final theme in _themes) theme.create(resolver)];

    // Discover all tests
    var testFiles = [
      for (final f in Directory(
        fixturePath('$themesTestPath/tests'),
      ).listSync())
        f.uri.pathSegments.last,
    ]..sort();
    testFiles = testFiles.where((f) => !f.endsWith('.result')).toList();
    testFiles = testFiles.where((f) => !f.endsWith('.result.patch')).toList();
    testFiles = testFiles.where((f) => !f.endsWith('.actual')).toList();
    testFiles = testFiles.where((f) => !f.endsWith('.diff.html')).toList();

    for (final testFile in testFiles) {
      final tst = ThemeTest(testFile, themeData, resolver);
      test(tst.testName, () async {
        await tst.evaluate();
        expect(tst.actual, tst.expected);
      }, timeout: const Timeout(Duration(seconds: 120)));
    }
  });

  test('Tokenize test1.ts with TypeScript grammar and dark_vs theme', () async {
    await testTokenizationTime('test1.ts');
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('Tokenize test2.ts with TypeScript grammar and dark_vs theme', () async {
    await testTokenizationTime('test2.ts');
  }, skip: 'fixtures/test2.ts (2.5 MB benchmark input) is not copied');

  test('Theme matching gives higher priority to deeper matches', () {
    final theme = Theme.createFromRawTheme(
      IRawTheme(
        settings: [
          _setting(null, foreground: '#100000', background: '#200000'),
          _setting(
            'punctuation.definition.string.begin.html',
            foreground: '#300000',
          ),
          _setting(
            'meta.tag punctuation.definition.string',
            foreground: '#400000',
          ),
        ],
      ),
    );
    final actual = theme.match(
      ScopeStack.from(['punctuation.definition.string.begin.html']),
    );
    expect(theme.getColorMap()[actual!.foregroundId], '#300000');
  });

  test('Theme matching gives higher priority to parent matches 1', () {
    final theme = Theme.createFromRawTheme(
      IRawTheme(
        settings: [
          _setting(null, foreground: '#100000', background: '#200000'),
          _setting('c a', foreground: '#300000'),
          _setting('d a.b', foreground: '#400000'),
          _setting('a', foreground: '#500000'),
        ],
      ),
    );

    final map = theme.getColorMap();

    expect(
      map[theme.match(ScopeStack.from(['d', 'a.b']))!.foregroundId],
      '#400000',
    );
  });

  test('Theme matching gives higher priority to parent matches 2', () {
    final theme = Theme.createFromRawTheme(
      IRawTheme(
        settings: [
          _setting(null, foreground: '#100000', background: '#200000'),
          _setting('meta.tag entity', foreground: '#300000'),
          _setting('meta.selector.css entity.name.tag', foreground: '#400000'),
          _setting('entity', foreground: '#500000'),
        ],
      ),
    );

    final result = theme.match(
      ScopeStack.from([
        'text.html.cshtml',
        'meta.tag.structure.any.html',
        'entity.name.tag.structure.any.html',
      ]),
    );

    final colorMap = theme.getColorMap();
    expect(colorMap[result!.foregroundId], '#300000');
  });

  group('Theme matching can match', () {
    final theme = Theme.createFromRawTheme(
      IRawTheme(
        settings: [
          _setting(null, foreground: '#F8F8F2', background: '#272822'),
          _setting('source, something', background: '#100000'),
          _setting(['bar', 'baz'], background: '#200000'),
          _setting('source.css selector bar', fontStyle: 'bold'),
          _setting('constant', fontStyle: 'italic', foreground: '#300000'),
          _setting('constant.numeric', foreground: '#400000'),
          _setting('constant.numeric.hex', fontStyle: 'bold'),
          _setting('constant.numeric.oct', fontStyle: 'bold italic underline'),
          _setting(
            'constant.numeric.dec',
            fontStyle: '',
            foreground: '#500000',
          ),
          _setting('storage.object.bar', fontStyle: '', foreground: '#600000'),
        ],
      ),
    );

    final map = theme.getColorMap();

    Map<String, Object?>? match(List<String> path) {
      final result = theme.match(ScopeStack.from(path));
      if (result == null) {
        return null;
      }
      final obj = <String, Object?>{
        'fontStyle': fontStyleToString(result.fontStyle),
      };
      if (result.foregroundId != 0) {
        obj['foreground'] = map[result.foregroundId];
      }
      if (result.backgroundId != 0) {
        obj['background'] = map[result.backgroundId];
      }
      return obj;
    }

    void check(String name, List<String> path, Map<String, Object?> expected) {
      test(name, () => expect(match(path), expected));
    }

    check(
      'simpleMatch1',
      ['source'],
      {'background': '#100000', 'fontStyle': 'not set'},
    );
    check(
      'simpleMatch2',
      ['source.ts'],
      {'background': '#100000', 'fontStyle': 'not set'},
    );
    check(
      'simpleMatch3',
      ['source.tss'],
      {'background': '#100000', 'fontStyle': 'not set'},
    );
    check(
      'simpleMatch4',
      ['something'],
      {'background': '#100000', 'fontStyle': 'not set'},
    );
    check(
      'simpleMatch5',
      ['something.ts'],
      {'background': '#100000', 'fontStyle': 'not set'},
    );
    check(
      'simpleMatch6',
      ['something.tss'],
      {'background': '#100000', 'fontStyle': 'not set'},
    );
    check(
      'simpleMatch7',
      ['baz'],
      {'background': '#200000', 'fontStyle': 'not set'},
    );
    check(
      'simpleMatch8',
      ['baz.ts'],
      {'background': '#200000', 'fontStyle': 'not set'},
    );
    check(
      'simpleMatch9',
      ['baz.tss'],
      {'background': '#200000', 'fontStyle': 'not set'},
    );
    check(
      'simpleMatch10',
      ['constant'],
      {'foreground': '#300000', 'fontStyle': 'italic'},
    );
    check(
      'simpleMatch11',
      ['constant.string'],
      {'foreground': '#300000', 'fontStyle': 'italic'},
    );
    check(
      'simpleMatch12',
      ['constant.hex'],
      {'foreground': '#300000', 'fontStyle': 'italic'},
    );
    check(
      'simpleMatch13',
      ['constant.numeric'],
      {'foreground': '#400000', 'fontStyle': 'italic'},
    );
    check(
      'simpleMatch14',
      ['constant.numeric.baz'],
      {'foreground': '#400000', 'fontStyle': 'italic'},
    );
    check(
      'simpleMatch15',
      ['constant.numeric.hex'],
      {'foreground': '#400000', 'fontStyle': 'bold'},
    );
    check(
      'simpleMatch16',
      ['constant.numeric.hex.baz'],
      {'foreground': '#400000', 'fontStyle': 'bold'},
    );
    check(
      'simpleMatch17',
      ['constant.numeric.oct'],
      {'foreground': '#400000', 'fontStyle': 'italic bold underline'},
    );
    check(
      'simpleMatch18',
      ['constant.numeric.oct.baz'],
      {'foreground': '#400000', 'fontStyle': 'italic bold underline'},
    );
    check(
      'simpleMatch19',
      ['constant.numeric.dec'],
      {'foreground': '#500000', 'fontStyle': 'none'},
    );
    check(
      'simpleMatch20',
      ['constant.numeric.dec.baz'],
      {'foreground': '#500000', 'fontStyle': 'none'},
    );
    check(
      'simpleMatch21',
      ['storage.object.bar'],
      {'foreground': '#600000', 'fontStyle': 'none'},
    );
    check(
      'simpleMatch22',
      ['storage.object.bar.baz'],
      {'foreground': '#600000', 'fontStyle': 'none'},
    );
    check('simpleMatch23', ['storage.object.bart'], {'fontStyle': 'not set'});
    check('simpleMatch24', ['storage.object'], {'fontStyle': 'not set'});
    check('simpleMatch25', ['storage'], {'fontStyle': 'not set'});

    check('defaultMatch1', [''], {'fontStyle': 'not set'});
    check('defaultMatch2', ['bazz'], {'fontStyle': 'not set'});
    check('defaultMatch3', ['asdfg'], {'fontStyle': 'not set'});

    check(
      'multiMatch1',
      ['bar'],
      {'background': '#200000', 'fontStyle': 'not set'},
    );
    check(
      'multiMatch2',
      ['source.css', 'selector', 'bar'],
      {'background': '#200000', 'fontStyle': 'bold'},
    );
  });

  test('Theme matching Microsoft/vscode#23460', () {
    final theme = Theme.createFromRawTheme(
      IRawTheme(
        settings: [
          _setting(null, foreground: '#aec2e0', background: '#14191f'),
          _setting(
            'meta.structure.dictionary.json string.quoted.double.json',
            name: 'JSON String',
            foreground: '#FF410D',
          ),
          _setting(
            'meta.structure.dictionary.json string.quoted.double.json',
            foreground: '#ffffff',
          ),
          _setting(
            'meta.structure.dictionary.value.json string.quoted.double.json',
            foreground: '#FF410D',
          ),
        ],
      ),
    );

    final path = ScopeStack.from([
      'source.json',
      'meta.structure.dictionary.json',
      'meta.structure.dictionary.value.json',
      'string.quoted.double.json',
    ]);
    final result = theme.match(path);
    expect(theme.getColorMap()[result!.foregroundId], '#FF410D');
  });

  test('Theme parsing can parse', () {
    final actual = parseTheme(
      IRawTheme(
        settings: [
          _setting(null, foreground: '#F8F8F2', background: '#272822'),
          _setting('source, something', background: '#100000'),
          _setting(['bar', 'baz'], background: '#010000'),
          _setting('source.css selector bar', fontStyle: 'bold'),
          _setting('constant', fontStyle: 'italic', foreground: '#ff0000'),
          _setting('constant.numeric', foreground: '#00ff00'),
          _setting('constant.numeric.hex', fontStyle: 'bold'),
          _setting('constant.numeric.oct', fontStyle: 'bold italic underline'),
          _setting('constant.numeric.bin', fontStyle: 'bold strikethrough'),
          _setting(
            'constant.numeric.dec',
            fontStyle: '',
            foreground: '#0000ff',
          ),
          _setting('foo', fontStyle: '', foreground: '#CFA'),
        ],
      ),
    );

    final expected = [
      ParsedThemeRule(
        '',
        null,
        0,
        FontStyle.notSet,
        '#F8F8F2',
        '#272822',
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        'source',
        null,
        1,
        FontStyle.notSet,
        null,
        '#100000',
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        'something',
        null,
        1,
        FontStyle.notSet,
        null,
        '#100000',
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        'bar',
        null,
        2,
        FontStyle.notSet,
        null,
        '#010000',
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        'baz',
        null,
        2,
        FontStyle.notSet,
        null,
        '#010000',
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        'bar',
        ['selector', 'source.css'],
        3,
        FontStyle.bold,
        null,
        null,
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        'constant',
        null,
        4,
        FontStyle.italic,
        '#ff0000',
        null,
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        'constant.numeric',
        null,
        5,
        FontStyle.notSet,
        '#00ff00',
        null,
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        'constant.numeric.hex',
        null,
        6,
        FontStyle.bold,
        null,
        null,
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        'constant.numeric.oct',
        null,
        7,
        FontStyle.bold | FontStyle.italic | FontStyle.underline,
        null,
        null,
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        'constant.numeric.bin',
        null,
        8,
        FontStyle.bold | FontStyle.strikethrough,
        null,
        null,
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        'constant.numeric.dec',
        null,
        9,
        FontStyle.none,
        '#0000ff',
        null,
        '',
        0,
        0,
      ),
      ParsedThemeRule('foo', null, 10, FontStyle.none, '#CFA', null, '', 0, 0),
    ];

    expect(_rules(actual), _rules(expected));
  });

  test('Theme resolving strcmp works', () {
    final actual = ['bar', 'z', 'zu', 'a', 'ab', '']..sort(strcmp);

    final expected = ['', 'a', 'ab', 'bar', 'z', 'zu'];
    expect(actual, expected);
  });

  test('Theme resolving strArrCmp works', () {
    void assertStrArrCmp(
      String testCase,
      List<String>? a,
      List<String>? b,
      int expected,
    ) {
      expect(strArrCmp(a, b), expected, reason: testCase);
    }

    assertStrArrCmp('001', null, null, 0);
    assertStrArrCmp('002', null, [], -1);
    assertStrArrCmp('003', null, ['a'], -1);
    assertStrArrCmp('004', [], null, 1);
    assertStrArrCmp('005', ['a'], null, 1);
    assertStrArrCmp('006', [], [], 0);
    assertStrArrCmp('007', [], ['a'], -1);
    assertStrArrCmp('008', ['a'], [], 1);
    assertStrArrCmp('009', ['a'], ['a'], 0);
    assertStrArrCmp('010', ['a', 'b'], ['a'], 1);
    assertStrArrCmp('011', ['a'], ['a', 'b'], -1);
    assertStrArrCmp('012', ['a', 'b'], ['a', 'b'], 0);
    assertStrArrCmp('013', ['a', 'b'], ['a', 'c'], -1);
    assertStrArrCmp('014', ['a', 'c'], ['a', 'b'], 1);
  });

  const numberNotSet = 0;
  const stringNotSet = '';

  ThemeTrieElementRule rule(
    int scopeDepth,
    List<String>? parentScopes,
    int fontStyle,
    int foreground,
    int background,
  ) => ThemeTrieElementRule(
    scopeDepth,
    parentScopes,
    fontStyle,
    foreground,
    background,
    stringNotSet,
    numberNotSet,
    numberNotSet,
  );

  StyleAttributes defaults(int fontStyle, int a, int b) => StyleAttributes(
    fontStyle,
    a,
    b,
    stringNotSet,
    numberNotSet,
    numberNotSet,
  );

  ThemeTrieElement rootElement([Map<String, ThemeTrieElement>? children]) =>
      ThemeTrieElement(
        rule(0, null, FontStyle.notSet, numberNotSet, numberNotSet),
        [],
        children,
      );

  test('Theme resolving always has defaults', () {
    final actual = Theme.createFromParsedTheme([]);
    final colorMap = ColorMap();
    final a = colorMap.getId('#000000');
    final b = colorMap.getId('#ffffff');
    final expected = Theme(
      colorMap,
      defaults(FontStyle.none, a, b),
      rootElement(),
    );
    assertThemeEqual(actual, expected);
  });

  test('Theme resolving respects incoming defaults 1', () {
    final actual = Theme.createFromParsedTheme([
      ParsedThemeRule('', null, -1, FontStyle.notSet, null, null, '', 0, 0),
    ]);
    final colorMap = ColorMap();
    final a = colorMap.getId('#000000');
    final b = colorMap.getId('#ffffff');
    final expected = Theme(
      colorMap,
      defaults(FontStyle.none, a, b),
      rootElement(),
    );
    assertThemeEqual(actual, expected);
  });

  test('Theme resolving respects incoming defaults 2', () {
    final actual = Theme.createFromParsedTheme([
      ParsedThemeRule('', null, -1, FontStyle.none, null, null, '', 0, 0),
    ]);
    final colorMap = ColorMap();
    final a = colorMap.getId('#000000');
    final b = colorMap.getId('#ffffff');
    final expected = Theme(
      colorMap,
      defaults(FontStyle.none, a, b),
      rootElement(),
    );
    assertThemeEqual(actual, expected);
  });

  test('Theme resolving respects incoming defaults 3', () {
    final actual = Theme.createFromParsedTheme([
      ParsedThemeRule('', null, -1, FontStyle.bold, null, null, '', 0, 0),
    ]);
    final colorMap = ColorMap();
    final a = colorMap.getId('#000000');
    final b = colorMap.getId('#ffffff');
    final expected = Theme(
      colorMap,
      defaults(FontStyle.bold, a, b),
      rootElement(),
    );
    assertThemeEqual(actual, expected);
  });

  test('Theme resolving respects incoming defaults 4', () {
    final actual = Theme.createFromParsedTheme([
      ParsedThemeRule(
        '',
        null,
        -1,
        FontStyle.notSet,
        '#ff0000',
        null,
        '',
        0,
        0,
      ),
    ]);
    final colorMap = ColorMap();
    final a = colorMap.getId('#ff0000');
    final b = colorMap.getId('#ffffff');
    final expected = Theme(
      colorMap,
      defaults(FontStyle.none, a, b),
      rootElement(),
    );
    assertThemeEqual(actual, expected);
  });

  test('Theme resolving respects incoming defaults 5', () {
    final actual = Theme.createFromParsedTheme([
      ParsedThemeRule(
        '',
        null,
        -1,
        FontStyle.notSet,
        null,
        '#ff0000',
        '',
        0,
        0,
      ),
    ]);
    final colorMap = ColorMap();
    final a = colorMap.getId('#000000');
    final b = colorMap.getId('#ff0000');
    final expected = Theme(
      colorMap,
      defaults(FontStyle.none, a, b),
      rootElement(),
    );
    assertThemeEqual(actual, expected);
  });

  test('Theme resolving can merge incoming defaults', () {
    final actual = Theme.createFromParsedTheme([
      ParsedThemeRule(
        '',
        null,
        -1,
        FontStyle.notSet,
        null,
        '#ff0000',
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        '',
        null,
        -1,
        FontStyle.notSet,
        '#00ff00',
        null,
        '',
        0,
        0,
      ),
      ParsedThemeRule('', null, -1, FontStyle.bold, null, null, '', 0, 0),
    ]);
    final colorMap = ColorMap();
    final a = colorMap.getId('#00ff00');
    final b = colorMap.getId('#ff0000');
    final expected = Theme(
      colorMap,
      defaults(FontStyle.bold, a, b),
      rootElement(),
    );
    assertThemeEqual(actual, expected);
  });

  test('Theme resolving defaults are inherited', () {
    final actual = Theme.createFromParsedTheme([
      ParsedThemeRule(
        '',
        null,
        -1,
        FontStyle.notSet,
        '#F8F8F2',
        '#272822',
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        'var',
        null,
        -1,
        FontStyle.notSet,
        '#ff0000',
        null,
        '',
        0,
        0,
      ),
    ]);
    final colorMap = ColorMap();
    final a = colorMap.getId('#F8F8F2');
    final b = colorMap.getId('#272822');
    final c = colorMap.getId('#ff0000');
    final expected = Theme(
      colorMap,
      defaults(FontStyle.none, a, b),
      rootElement({
        'var': ThemeTrieElement(
          rule(1, null, FontStyle.notSet, c, numberNotSet),
        ),
      }),
    );
    assertThemeEqual(actual, expected);
  });

  test('Theme resolving same rules get merged', () {
    final actual = Theme.createFromParsedTheme([
      ParsedThemeRule(
        '',
        null,
        -1,
        FontStyle.notSet,
        '#F8F8F2',
        '#272822',
        '',
        0,
        0,
      ),
      ParsedThemeRule('var', null, 1, FontStyle.bold, null, null, '', 0, 0),
      ParsedThemeRule(
        'var',
        null,
        0,
        FontStyle.notSet,
        '#ff0000',
        null,
        '',
        0,
        0,
      ),
    ]);
    final colorMap = ColorMap();
    final a = colorMap.getId('#F8F8F2');
    final b = colorMap.getId('#272822');
    final c = colorMap.getId('#ff0000');
    final expected = Theme(
      colorMap,
      defaults(FontStyle.none, a, b),
      rootElement({
        'var': ThemeTrieElement(rule(1, null, FontStyle.bold, c, numberNotSet)),
      }),
    );
    assertThemeEqual(actual, expected);
  });

  test('Theme resolving rules are inherited 1', () {
    final actual = Theme.createFromParsedTheme([
      ParsedThemeRule(
        '',
        null,
        -1,
        FontStyle.notSet,
        '#F8F8F2',
        '#272822',
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        'var',
        null,
        -1,
        FontStyle.bold,
        '#ff0000',
        null,
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        'var.identifier',
        null,
        -1,
        FontStyle.notSet,
        '#00ff00',
        null,
        '',
        0,
        0,
      ),
    ]);
    final colorMap = ColorMap();
    final a = colorMap.getId('#F8F8F2');
    final b = colorMap.getId('#272822');
    final c = colorMap.getId('#ff0000');
    final d = colorMap.getId('#00ff00');
    final expected = Theme(
      colorMap,
      defaults(FontStyle.none, a, b),
      rootElement({
        'var': ThemeTrieElement(
          rule(1, null, FontStyle.bold, c, numberNotSet),
          [],
          {
            'identifier': ThemeTrieElement(
              rule(2, null, FontStyle.bold, d, numberNotSet),
            ),
          },
        ),
      }),
    );
    assertThemeEqual(actual, expected);
  });

  test('Theme resolving rules are inherited 2', () {
    final actual = Theme.createFromParsedTheme([
      ParsedThemeRule(
        '',
        null,
        -1,
        FontStyle.notSet,
        '#F8F8F2',
        '#272822',
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        'var',
        null,
        -1,
        FontStyle.bold,
        '#ff0000',
        null,
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        'var.identifier',
        null,
        -1,
        FontStyle.notSet,
        '#00ff00',
        null,
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        'constant',
        null,
        4,
        FontStyle.italic,
        '#100000',
        null,
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        'constant.numeric',
        null,
        5,
        FontStyle.notSet,
        '#200000',
        null,
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        'constant.numeric.hex',
        null,
        6,
        FontStyle.bold,
        null,
        null,
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        'constant.numeric.oct',
        null,
        7,
        FontStyle.bold | FontStyle.italic | FontStyle.underline,
        null,
        null,
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        'constant.numeric.dec',
        null,
        8,
        FontStyle.none,
        '#300000',
        null,
        '',
        0,
        0,
      ),
    ]);
    final colorMap = ColorMap();
    final a = colorMap.getId('#F8F8F2');
    final b = colorMap.getId('#272822');
    final c = colorMap.getId('#100000');
    final d = colorMap.getId('#200000');
    final e = colorMap.getId('#300000');
    final f = colorMap.getId('#ff0000');
    final g = colorMap.getId('#00ff00');
    final expected = Theme(
      colorMap,
      defaults(FontStyle.none, a, b),
      rootElement({
        'var': ThemeTrieElement(
          rule(1, null, FontStyle.bold, f, numberNotSet),
          [],
          {
            'identifier': ThemeTrieElement(
              rule(2, null, FontStyle.bold, g, numberNotSet),
            ),
          },
        ),
        'constant': ThemeTrieElement(
          rule(1, null, FontStyle.italic, c, numberNotSet),
          [],
          {
            'numeric': ThemeTrieElement(
              rule(2, null, FontStyle.italic, d, numberNotSet),
              [],
              {
                'hex': ThemeTrieElement(
                  rule(3, null, FontStyle.bold, d, numberNotSet),
                ),
                'oct': ThemeTrieElement(
                  rule(
                    3,
                    null,
                    FontStyle.bold | FontStyle.italic | FontStyle.underline,
                    d,
                    numberNotSet,
                  ),
                ),
                'dec': ThemeTrieElement(
                  rule(3, null, FontStyle.none, e, numberNotSet),
                ),
              },
            ),
          },
        ),
      }),
    );
    assertThemeEqual(actual, expected);
  });

  test('Theme resolving rules with parent scopes', () {
    final actual = Theme.createFromParsedTheme([
      ParsedThemeRule(
        '',
        null,
        -1,
        FontStyle.notSet,
        '#F8F8F2',
        '#272822',
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        'var',
        null,
        -1,
        FontStyle.bold,
        '#100000',
        null,
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        'var.identifier',
        null,
        -1,
        FontStyle.notSet,
        '#200000',
        null,
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        'var',
        ['source.css'],
        1,
        FontStyle.italic,
        '#300000',
        null,
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        'var',
        ['source.css'],
        2,
        FontStyle.underline,
        null,
        null,
        '',
        0,
        0,
      ),
    ]);
    final colorMap = ColorMap();
    final a = colorMap.getId('#F8F8F2');
    final b = colorMap.getId('#272822');
    final c = colorMap.getId('#100000');
    final d = colorMap.getId('#300000');
    final e = colorMap.getId('#200000');
    final expected = Theme(
      colorMap,
      defaults(FontStyle.none, a, b),
      rootElement({
        'var': ThemeTrieElement(
          rule(1, null, FontStyle.bold, c, 0),
          [
            rule(1, ['source.css'], FontStyle.underline, d, numberNotSet),
          ],
          {
            'identifier': ThemeTrieElement(
              rule(2, null, FontStyle.bold, e, numberNotSet),
              [
                rule(1, ['source.css'], FontStyle.underline, d, numberNotSet),
              ],
            ),
          },
        ),
      }),
    );
    assertThemeEqual(actual, expected);
  });

  test('Theme resolving a rule with child combinator', () {
    final theme = Theme.createFromRawTheme(
      IRawTheme(
        settings: [
          _setting(null, foreground: '#100000'),
          _setting('b a', foreground: '#200000'),
          _setting('b > a', foreground: '#300000'),
          _setting('c > b > a', foreground: '#400000'),
          _setting('a', foreground: '#500000'),
        ],
      ),
    );

    final colorMap = theme.getColorMap();
    String? match(List<String> path) {
      final result = theme.match(ScopeStack.from(path));
      if (result == null) {
        return null;
      }
      return colorMap[result.foregroundId];
    }

    expect(match(['b', 'a']), '#300000', reason: 'b a');
    expect(match(['b', 'c', 'a']), '#200000', reason: 'b c a');
    expect(match(['c', 'b', 'a']), '#400000', reason: 'c b a');
    expect(match(['c', 'b', 'd', 'a']), '#200000', reason: 'c b d a');
  });

  test(
    'Theme resolving should give deeper scopes higher specificity (#233)',
    () {
      final theme = Theme.createFromRawTheme(
        IRawTheme(
          settings: [
            _setting(null, foreground: '#100000'),
            _setting('y.z a.b', foreground: '#200000'),
            _setting('x y a.b', foreground: '#300000'),
          ],
        ),
      );

      final colorMap = theme.getColorMap();
      theme.getDefaults();

      String? match(List<String> path) {
        final result = theme.match(ScopeStack.from(path));
        if (result == null || result.foregroundId == 0) {
          return null;
        }
        return colorMap[result.foregroundId];
      }

      // Sanity check
      expect(match(['x', 'a.b']), null, reason: 'x a.b');
      expect(match(['y', 'a.b']), null, reason: 'y a.b');
      expect(match(['y.z', 'a']), null, reason: 'y.z a');
      expect(match(['x', 'y', 'a.b']), '#300000', reason: 'x y a.b');

      // Even though the "x y a.b" rule has more scopes in its path, the "y.z a.b" rule has
      // a deeper match, so it should take precedence.
      expect(match(['x', 'y.z', 'a.b']), '#200000', reason: 'y.z a.b');
    },
  );

  test('Theme resolving issue #38: ignores rules with invalid colors', () {
    final actual = parseTheme(
      IRawTheme(
        settings: [
          _setting(null, background: '#222222', foreground: '#cccccc'),
          _setting('variable', name: 'Variable', fontStyle: ''),
          _setting(
            'variable.parameter',
            name: 'Function argument',
            fontStyle: 'italic',
            foreground: '',
          ),
          _setting(
            'support.other.variable',
            name: 'Library variable',
            fontStyle: '',
          ),
          _setting(
            'variable.other',
            name: 'Function argument',
            foreground: '',
            fontStyle: 'normal',
          ),
          _setting(
            'variable.parameter.function.coffee',
            name: 'Coffeescript Function argument',
            foreground: '#F9D423',
            fontStyle: 'italic',
          ),
        ],
      ),
    );

    final expected = [
      ParsedThemeRule(
        '',
        null,
        0,
        FontStyle.notSet,
        '#cccccc',
        '#222222',
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        'variable',
        null,
        1,
        FontStyle.none,
        null,
        null,
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        'variable.parameter',
        null,
        2,
        FontStyle.italic,
        null,
        null,
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        'support.other.variable',
        null,
        3,
        FontStyle.none,
        null,
        null,
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        'variable.other',
        null,
        4,
        FontStyle.none,
        null,
        null,
        '',
        0,
        0,
      ),
      ParsedThemeRule(
        'variable.parameter.function.coffee',
        null,
        5,
        FontStyle.italic,
        '#F9D423',
        null,
        '',
        0,
        0,
      ),
    ];

    expect(_rules(actual), _rules(expected));
  });

  test(
    'Theme resolving issue #35: Trailing comma in a tmTheme scope selector',
    () {
      final actual = parseTheme(
        IRawTheme(
          settings: [
            _setting(null, background: '#25292C', foreground: '#EFEFEF'),
            _setting(
              [
                'meta.at-rule.return.scss,',
                'meta.at-rule.return.scss punctuation.definition,',
                'meta.at-rule.else.scss,',
                'meta.at-rule.else.scss punctuation.definition,',
                'meta.at-rule.if.scss,',
                'meta.at-rule.if.scss punctuation.definition,',
              ].join('\n'),
              name: 'CSS at-rule keyword control',
              foreground: '#CC7832',
            ),
          ],
        ),
      );

      final expected = [
        ParsedThemeRule(
          '',
          null,
          0,
          FontStyle.notSet,
          '#EFEFEF',
          '#25292C',
          '',
          0,
          0,
        ),
        ParsedThemeRule(
          'meta.at-rule.return.scss',
          null,
          1,
          FontStyle.notSet,
          '#CC7832',
          null,
          '',
          0,
          0,
        ),
        ParsedThemeRule(
          'punctuation.definition',
          ['meta.at-rule.return.scss'],
          1,
          FontStyle.notSet,
          '#CC7832',
          null,
          '',
          0,
          0,
        ),
        ParsedThemeRule(
          'meta.at-rule.else.scss',
          null,
          1,
          FontStyle.notSet,
          '#CC7832',
          null,
          '',
          0,
          0,
        ),
        ParsedThemeRule(
          'punctuation.definition',
          ['meta.at-rule.else.scss'],
          1,
          FontStyle.notSet,
          '#CC7832',
          null,
          '',
          0,
          0,
        ),
        ParsedThemeRule(
          'meta.at-rule.if.scss',
          null,
          1,
          FontStyle.notSet,
          '#CC7832',
          null,
          '',
          0,
          0,
        ),
        ParsedThemeRule(
          'punctuation.definition',
          ['meta.at-rule.if.scss'],
          1,
          FontStyle.notSet,
          '#CC7832',
          null,
          '',
          0,
          0,
        ),
      ];

      expect(_rules(actual), _rules(expected));
    },
  );
}
