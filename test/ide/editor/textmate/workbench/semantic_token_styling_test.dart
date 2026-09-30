// The Dart semantic token styling against VS Code: for every bundled theme
// (and two synthetic ones), the metadata `SemanticTokensProviderStyling`
// computes for each token type × modifier set × language must equal what
// tool/generate_semantic_token_fixtures.mjs recorded from the upstream code
// (test/fixtures/theme/semantic_tokens.json.gz), as must the registry, the
// built-in extensions' contributions and the selector scores.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/services/semantic_tokens_provider_styling.dart';
import 'package:monad/ide/editor/monaco/vs/platform/theme/common/token_classification_registry.dart';
import 'package:monad/ide/editor/monaco/vs/workbench/services/themes/common/color_theme_data.dart';
import 'package:monad/ide/editor/monaco/vs/workbench/services/themes/common/color_theme_token_styles.dart';
import 'package:monad/ide/editor/monaco/vs/workbench/services/themes/common/token_classification_extension_point.dart';
import 'package:monad/ide/editor/monaco/vs/workbench/services/themes/common/workbench_theme_service.dart';
import 'package:monad/ide/editor/textmate/textmate_manifest.dart';

const fixturePath = 'test/fixtures/theme/semantic_tokens.json.gz';

Map<String, Object?> readSemanticTokenFixture() =>
    jsonDecode(utf8.decode(gzip.decode(File(fixturePath).readAsBytesSync())))
        as Map<String, Object?>;

void main() {
  final fixture = readSemanticTokenFixture();
  final manifest = TextMateManifest.parse(
    File('$textMateAssetRoot/manifest.json').readAsStringSync(),
  );
  final legend = fixture['legend'] as Map<String, Object?>;
  final tokenTypes = (legend['tokenTypes'] as List).cast<String>();
  final tokenModifiers = (legend['tokenModifiers'] as List).cast<String>();
  final modifierSets = (fixture['modifierSets'] as List).cast<int>();
  final languages = (fixture['languages'] as List).cast<String>();

  test('fixture revision', () {
    expect(fixture['revision'], manifest.revision);
  });

  group('registry', () {
    final registry = getWorkbenchTokenClassificationRegistry();

    test('built-in contributions are what upstream registers', () {
      expect([
        for (final c in builtinTokenClassificationContributions)
          {
            'extension': c.extensionId,
            'semanticTokenTypes': ?c.semanticTokenTypes,
            'semanticTokenModifiers': ?c.semanticTokenModifiers,
            'semanticTokenScopes': ?c.semanticTokenScopes,
          },
      ], fixture['contributions']);
      final points = TokenClassificationExtensionPoints(
        TokenClassificationRegistry(),
      )..handle(builtinTokenClassificationContributions);
      expect(points.errors, isEmpty);
    });

    test('types, modifiers and default rules', () {
      expect([
        for (final t in registry.getTokenTypes())
          {'id': t.id, 'superType': t.superType},
      ], fixture['tokenTypes']);
      expect([
        for (final m in registry.getTokenModifiers()) m.id,
      ], fixture['tokenModifiers']);
      expect([
        for (final r in registry.getTokenStylingDefaultRules())
          {
            'selector': r.selector.id,
            'scopesToProbe': r.defaults.scopesToProbe,
          },
      ], fixture['defaultRules']);
    });

    test('selectors', () {
      final probes = [
        for (final probe in fixture['selectorProbes'] as List)
          (
            (probe as List)[0] as String,
            (probe[1] as List).cast<String>(),
            probe[2] as String,
          ),
      ];
      for (final entry in fixture['selectors'] as List) {
        final e = entry as Map<String, Object?>;
        final selector = registry.parseTokenSelector(
          e['selector'] as String,
          e['language'] as String?,
        );
        expect(selector.id, e['id'], reason: '${e['selector']}');
        expect(
          [for (final (t, m, l) in probes) selector.match(t, m, l)],
          e['scores'],
          reason: '${e['selector']} ${e['language']}',
        );
      }
    });
  });

  /// Replays one theme's matrix; the differences, described.
  List<String> replay(ColorThemeData theme, Map<String, Object?> expected) {
    final styles = ColorThemeTokenStyles(theme);
    final styling = SemanticTokensProviderStyling(
      SemanticTokensLegend(
        tokenTypes: tokenTypes,
        tokenModifiers: tokenModifiers,
      ),
      styles.getTokenStyleMetadata,
    );
    final metadata = (expected['metadata'] as List).cast<int>();
    final matrix = (expected['matrix'] as List).cast<int>();
    final differences = <String>[];
    var i = 0;
    for (final language in languages) {
      for (var type = 0; type < tokenTypes.length; type++) {
        for (final set in modifierSets) {
          final want = metadata[matrix[i++]];
          final got = styling.getMetadata(type, set, language);
          if (got != want) {
            final modifiers = [
              for (var m = 0; m < tokenModifiers.length; m++)
                if (set & (1 << m) != 0) tokenModifiers[m],
            ];
            differences.add(
              '$language ${tokenTypes[type]} $modifiers: '
              '0x${got.toRadixString(16)} != 0x${want.toRadixString(16)}',
            );
          }
        }
      }
    }
    return differences;
  }

  group('bundled themes match VS Code', () {
    for (final entry in fixture['themes'] as List) {
      final expected = entry as Map<String, Object?>;
      test(expected['id'] as String, () async {
        final contribution = manifest.themeById(expected['id'] as String)!;
        final theme = ColorThemeData.fromExtensionTheme(
          contribution,
          contribution.assetPath,
          extensionId: contribution.extensionId,
        );
        await theme.ensureLoaded(
          (path) => File('$textMateAssetRoot/$path').readAsString(),
        );
        expect(theme.type.value, expected['type']);
        expect(theme.semanticHighlighting, expected['semanticHighlighting']);
        expect(theme.tokenColorMap, expected['tokenColorMap']);
        expect(replay(theme, expected), isEmpty);
      });
    }
  });

  group('synthetic themes match VS Code', () {
    for (final entry in fixture['syntheticThemes'] as List) {
      final expected = entry as Map<String, Object?>;
      test(expected['id'] as String, () async {
        final files = (expected['files'] as Map).cast<String, String>();
        final path = expected['path'] as String;
        final theme = ColorThemeData.fromExtensionTheme(
          IThemeExtensionPoint(
            id: expected['id'] as String,
            label: expected['id'] as String,
            path: './$path',
            uiTheme: expected['uiTheme'] as String,
          ),
          '/synthetic/$path',
          extensionId: 'test.synthetic',
        );
        await theme.ensureLoaded(
          (location) async => files[location.substring('/synthetic/'.length)]!,
        );
        expect(theme.type.value, expected['type']);
        expect(theme.semanticHighlighting, expected['semanticHighlighting']);
        expect(theme.tokenColorMap, expected['tokenColorMap']);
        expect(replay(theme, expected), isEmpty);
      });
    }
  });

  test('TokenStyle.fromSettings reads font styles as upstream', () {
    final style = TokenStyle.fromSettings(
      '#ff0000',
      'bold italic',
      true,
      true,
      TokenStyle.absent,
      TokenStyle.absent,
    );
    expect(style.foreground.toString(), '#ff0000');
    expect(
      (style.bold, style.italic, style.underline, style.strikethrough),
      (true, true, false, false),
    );
    // Without a font style, the flags stay as given (absent is undefined).
    final flags = TokenStyle.fromSettings(
      null,
      TokenStyle.absent,
      false,
      TokenStyle.absent,
      null,
      TokenStyle.absent,
    );
    expect(
      (flags.bold, flags.underline, flags.strikethrough, flags.italic),
      (false, null, false, null),
    );
  });
}
