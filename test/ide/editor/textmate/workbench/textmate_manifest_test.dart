// The bundled manifest (tool/generate_textmate_assets.mjs) and the grammar
// definitions VS Code's tokenization feature derives from it, checked against
// the language ids tool/generate_textmate_fixtures.mjs recorded.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/monaco/vs/base/common/json.dart' as json;
import 'package:monad/ide/editor/monaco/vs/editor/common/encoded_token_attributes.dart';
import 'package:monad/ide/editor/monaco/vs/workbench/services/text_mate/browser/text_mate_tokenization_feature_impl.dart';
import 'package:monad/ide/editor/monaco/vs/workbench/services/text_mate/common/tm_grammars.dart';
import 'package:monad/ide/editor/monaco/vs/workbench/services/text_mate/common/tm_scope_registry.dart';
import 'package:monad/ide/editor/textmate/textmate_manifest.dart';
import 'package:monad/ide/editor/textmate/vscode_textmate/main.dart'
    show parseRawGrammar;

import '../textmate_fixture.dart';

void main() {
  final manifest = TextMateManifest.parse(
    File('$textMateAssetRoot/manifest.json').readAsStringSync(),
  );
  final fixture = loadTextMateFixture();
  final languageIds = (fixture['languageIds'] as Map<String, Object?>)
      .cast<String, int>();

  IValidGrammarDefinition? validate(ITMSyntaxExtensionPoint grammar) =>
      validateGrammarDefinition(
        grammar,
        isRegisteredLanguageId: languageIds.containsKey,
        encodeLanguageId: (id) => languageIds[id]!,
      );

  group('manifest', () {
    test('matches the fixtures', () {
      expect(manifest.revision, fixture['revision']);
      expect(manifest.revision, '6a598d4a13031703d483d103c1d934a36ad27971');
      expect(
        fixture['defaultMaxTokenizationLineLength'],
        maxTokenizationLineLength,
      );
      expect(fixture['timeLimitMs'], tokenizationTimeLimitMs);
      // LanguageIdCodec: each id numbered from 1 at its first registration.
      expect(manifest.languageIds, languageIds.keys);
      expect(languageIds.values, [
        for (var i = 1; i <= languageIds.length; i++) i,
      ]);
      expect(languageIds['plaintext'], 1);
    });

    test('every file it names is bundled', () {
      final paths = [
        for (final grammar in manifest.grammars) grammar.path,
        for (final theme in manifest.themes) theme.assetPath,
        for (final language in manifest.languages) ?language.configuration,
      ];
      for (final path in paths) {
        expect(
          File('$textMateAssetRoot/$path').existsSync(),
          isTrue,
          reason: path,
        );
      }
      for (final language in manifest.languages) {
        final configuration = language.configuration;
        if (configuration == null) continue;
        final errors = <json.ParseError>[];
        json.parse(
          File('$textMateAssetRoot/$configuration').readAsStringSync(),
          errors,
        );
        expect(errors, isEmpty, reason: configuration);
      }
    });

    test('languages', () {
      final plaintext = manifest.languages.first;
      expect(plaintext.id, 'plaintext');
      expect(plaintext.extension, isNull);
      expect(plaintext.extensions, ['.txt']);
      expect(plaintext.aliases, ['Plain Text', 'text']);
      expect(plaintext.mimetypes, ['text/plain']);
      // Built-in extensions by folder name, then package.json order.
      expect(manifest.languages.skip(1).take(6).map((l) => l.id), [
        'bat',
        'clojure',
        'coffeescript',
        'jsonc',
        'json',
        'ignore',
      ]);
      final extensions = [
        for (final language in manifest.languages.skip(1)) language.extension!,
      ];
      for (var i = 1; i < extensions.length; i++) {
        expect(
          extensions[i - 1].compareTo(extensions[i]),
          lessThanOrEqualTo(0),
          reason: extensions[i],
        );
      }
      expect(extensions, isNot(contains('vscode-colorize-tests')));
      expect(extensions, contains('copilot'));
      expect(
        manifest.languages.where((l) => l.id == 'json').map((l) => l.extension),
        ['configuration-editing', 'json', 'typescript-basics'],
      );

      final typescript = manifest.languageById('typescript')!;
      expect(typescript.extension, 'typescript-basics');
      expect(typescript.extensions, ['.ts', '.cts', '.mts']);
      expect(typescript.aliases.first, 'TypeScript');
      expect(
        typescript.configuration,
        'grammars/typescript-basics/language-configuration.json',
      );
      expect(typescript.hasAliases, isTrue);
      expect(manifest.languageById('typescriptreact')!.extensions, ['.tsx']);
      final jsxTags = manifest.languageById('jsx-tags')!;
      expect(jsxTags.extension, 'javascript');
      expect(jsxTags.hasAliases, isTrue);
      expect(jsxTags.aliases, isEmpty);
      expect(manifest.languageById('javascript')!.firstLine, isNotNull);
      final gitRebase = manifest.languageById('git-rebase')!;
      expect(gitRebase.hasAliases, isTrue);
      expect(gitRebase.filenamePatterns, ['**/rebase-merge/done']);
      expect(manifest.languageById('dockerfile')!.filenames, isNotEmpty);
      expect(manifest.maxTokenizationLineLengthOf('javascript'), 2500);
      expect(manifest.maxTokenizationLineLengthOf('csharp'), 2500);
      expect(manifest.maxTokenizationLineLengthOf('typescript'), isNull);
    });

    test('grammars', () {
      expect(manifest.grammarForLanguage('typescript')!.scopeName, 'source.ts');
      expect(
        manifest.grammarForLanguage('typescriptreact')!.scopeName,
        'source.tsx',
      );
      expect(manifest.grammarForScope('documentation.injection.ts')!.injectTo, [
        'source.ts',
        'source.tsx',
      ]);
      // Several grammars share a scope name; VS Code keeps the last.
      expect(manifest.grammarForScope('source.ini')!.language, 'properties');
      expect(manifest.grammarForLanguage('ini')!.scopeName, 'source.ini');
      expect(
        manifest.grammarForScope('text.html.derivative')!.language,
        'html',
      );
      for (final grammar in manifest.grammars) {
        final raw = parseRawGrammar(
          File('$textMateAssetRoot/${grammar.path}').readAsStringSync(),
          grammar.path,
        );
        expect(raw.scopeName, grammar.scopeName, reason: grammar.path);
      }
    });

    test('themes', () {
      // VS Code's 19 but Light (Visual Studio) and Light+, which the assets
      // leave out.
      expect(manifest.themes, hasLength(17));
      expect(manifest.themeById('Visual Studio Light'), isNull);
      expect(manifest.themeById('Light+'), isNull);
      final darkPlus = manifest.themeById('Dark+')!;
      expect(darkPlus.extension, 'theme-defaults');
      expect(darkPlus.extensionId, 'vscode.theme-defaults');
      expect(darkPlus.uiTheme, 'vs-dark');
      expect(darkPlus.path, 'themes/dark_plus.json');
      expect(darkPlus.assetPath, 'themes/theme-defaults/themes/dark_plus.json');
      expect(
        manifest.themeById('Visual Studio Dark')!.label,
        'Dark (Visual Studio)',
      );
      for (final theme in manifest.themes) {
        expect(
          File('test/fixtures/textmate/themes/${theme.id}.json').existsSync(),
          isTrue,
          reason: theme.id,
        );
      }
    });

    test('rejects malformed entries', () {
      expect(() => TextMateManifest.parse('{}'), throwsFormatException);
      expect(
        () => TextMateManifest.parse(
          '{"revision": "r", "grammars": [{"extension": "x", "path": "p"}], '
          '"languages": [], "themes": []}',
        ),
        throwsFormatException,
      );
      expect(
        () => TextMateManifest.parse(
          '{"revision": "r", "grammars": [], "languages": [], "themes": '
          '[{"extension": "x", "id": "i", "label": "l", "path": "themes/y/t.json"}]}',
        ),
        throwsFormatException,
      );
    });
  });

  group('validateGrammarDefinition', () {
    const tokenTypes = {
      'punctuation.definition.template-expression': StandardTokenType.other,
      'entity.name.type.instance.jsdoc': StandardTokenType.other,
      'entity.name.function.tagged-template': StandardTokenType.other,
      'meta.import string.quoted': StandardTokenType.other,
      'variable.other.jsdoc': StandardTokenType.other,
    };

    test('TypeScript', () {
      final def = validate(manifest.grammarForLanguage('typescript')!)!;
      expect(def.language, 'typescript');
      expect(def.scopeName, 'source.ts');
      expect(
        def.location,
        'grammars/typescript-basics/syntaxes/TypeScript.tmLanguage.json',
      );
      expect(def.embeddedLanguages, isEmpty);
      expect(def.tokenTypes, tokenTypes);
      expect(def.injectTo, isNull);
      expect(def.balancedBracketSelectors, ['*']);
      expect(def.unbalancedBracketSelectors, [
        'keyword.operator.relational',
        'storage.type.function.arrow',
        'keyword.operator.bitwise.shift',
        'meta.brace.angle',
        'punctuation.definition.tag',
        'keyword.operator.assignment.compound.bitwise.ts',
      ]);
    });

    test('TypeScript React', () {
      final def = validate(manifest.grammarForLanguage('typescriptreact')!)!;
      expect(def.embeddedLanguages, {
        'meta.tag.tsx': languageIds['jsx-tags'],
        'meta.tag.without-attributes.tsx': languageIds['jsx-tags'],
        'meta.tag.attributes.tsx': languageIds['typescriptreact'],
        'meta.embedded.expression.tsx': languageIds['typescriptreact'],
      });
      expect(def.tokenTypes, tokenTypes);
      expect(def.balancedBracketSelectors, ['*']);
      expect(def.unbalancedBracketSelectors, [
        'keyword.operator.relational',
        'storage.type.function.arrow',
        'keyword.operator.bitwise.shift',
        'punctuation.definition.tag',
        'keyword.operator.assignment.compound.bitwise.ts',
      ]);
    });

    test('injections', () {
      final def = validate(
        manifest.grammarForScope('documentation.injection.ts')!,
      )!;
      expect(def.language, isNull);
      expect(def.injectTo, ['source.ts', 'source.tsx']);
      expect(def.embeddedLanguages, isEmpty);
      expect(def.tokenTypes, isEmpty);
      expect(def.balancedBracketSelectors, ['*']);
      expect(def.unbalancedBracketSelectors, isEmpty);
    });

    test('unregistered languages and unknown token types', () {
      expect(
        validate(
          const ITMSyntaxExtensionPoint(
            language: 'no-such-language',
            scopeName: 'source.js',
            path: 'x',
          ),
        ),
        isNull,
      );
      final def = validate(
        ITMSyntaxExtensionPoint.fromJson({
          'scopeName': 'source.x',
          'path': 'x',
          'embeddedLanguages': {'a': 'typescript', 'b': 'no-such', 'c': 1},
          'tokenTypes': {
            'a': 'string',
            'b': 'comment',
            'c': 'regex',
            'd': 'other',
            'e': 'keyword',
          },
          'balancedBracketScopes': ['x', 1],
          'unbalancedBracketScopes': 'y',
        }),
      )!;
      expect(def.embeddedLanguages, {'a': languageIds['typescript']});
      expect(def.tokenTypes, {
        'a': StandardTokenType.string,
        'b': StandardTokenType.comment,
        'c': StandardTokenType.regEx,
        'd': StandardTokenType.other,
      });
      expect(def.balancedBracketSelectors, ['*']);
      expect(def.unbalancedBracketSelectors, isEmpty);
    });

    test('malformed contributions', () {
      for (final entry in <Map<String, Object?>>[
        {'scopeName': 'a'},
        {'path': 'a'},
        {'scopeName': '', 'path': 'a'},
        {'scopeName': 'a', 'path': 'a', 'language': 1},
        {'scopeName': 'a', 'path': 'a', 'injectTo': 'b'},
        {'scopeName': 'a', 'path': 'a', 'embeddedLanguages': []},
      ]) {
        expect(
          () => ITMSyntaxExtensionPoint.fromJson(entry),
          throwsFormatException,
          reason: '$entry',
        );
      }
    });
  });
}
