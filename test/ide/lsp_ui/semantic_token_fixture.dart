// Expected semantic token styles from the upstream golden data
// (test/fixtures/theme/semantic_tokens.json.gz, written by
// tool/generate_semantic_token_fixtures.mjs), decoded here independently of
// the code under test.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:monad/ide/editor/monaco/vs/workbench/services/themes/common/color_theme_data.dart';
import 'package:monad/ide/editor/monaco/vs/workbench/services/themes/common/workbench_theme_service.dart';
import 'package:monad/ide/editor/textmate/textmate_manifest.dart';
import 'package:monad/ide/lsp_ui/semantic_tokens.dart';

class SemanticTokenFixture {
  SemanticTokenFixture._(Map<String, Object?> json)
    : _json = json,
      tokenTypes = ((json['legend'] as Map)['tokenTypes'] as List)
          .cast<String>(),
      tokenModifiers = ((json['legend'] as Map)['tokenModifiers'] as List)
          .cast<String>(),
      modifierSets = (json['modifierSets'] as List).cast<int>(),
      languages = (json['languages'] as List).cast<String>();

  static final SemanticTokenFixture instance = SemanticTokenFixture._(
    jsonDecode(
      utf8.decode(
        gzip.decode(
          File('test/fixtures/theme/semantic_tokens.json.gz').readAsBytesSync(),
        ),
      ),
    ) as Map<String, Object?>,
  );

  final Map<String, Object?> _json;

  /// The legend's token types and modifiers, the recorded modifier sets (as
  /// legend bit sets) and languages.
  final List<String> tokenTypes;
  final List<String> tokenModifiers;
  final List<int> modifierSets;
  final List<String> languages;

  List<Map<String, Object?>> get _bundled =>
      (_json['themes'] as List).cast<Map<String, Object?>>();
  List<Map<String, Object?>> get _synthetic =>
      (_json['syntheticThemes'] as List).cast<Map<String, Object?>>();

  /// The bundled themes, in manifest order.
  List<String> get themeIds => [for (final t in _bundled) t['id'] as String];

  Map<String, Object?> _theme(String id) =>
      [..._bundled, ..._synthetic].firstWhere((t) => t['id'] == id);

  bool semanticHighlighting(String themeId) =>
      _theme(themeId)['semanticHighlighting'] as bool;

  Set<String> modifiersOf(int set) => {
    for (var i = 0; i < tokenModifiers.length; i++)
      if (set & (1 << i) != 0) tokenModifiers[i],
  };

  /// VS Code's metadata for the token (a recorded combination).
  int metadata(
    String themeId,
    String type,
    Set<String> modifiers,
    String language,
  ) {
    final theme = _theme(themeId);
    final typeIndex = tokenTypes.indexOf(type);
    var bits = 0;
    for (final modifier in modifiers) {
      final index = tokenModifiers.indexOf(modifier);
      if (index < 0) throw ArgumentError.value(modifier, 'modifier');
      bits |= 1 << index;
    }
    final setIndex = modifierSets.indexOf(bits);
    final languageIndex = languages.indexOf(language);
    if (typeIndex < 0 || setIndex < 0 || languageIndex < 0) {
      throw ArgumentError('Not recorded: $type $modifiers $language');
    }
    final matrix = theme['matrix'] as List;
    final index =
        (languageIndex * tokenTypes.length + typeIndex) * modifierSets.length +
        setIndex;
    return (theme['metadata'] as List)[matrix[index] as int] as int;
  }

  /// VS Code's style for the token, decoded from its metadata: null when it
  /// styles nothing (`NO_STYLING`).
  IdeTokenStyle? style(
    String themeId,
    String type,
    Set<String> modifiers,
    String language,
  ) {
    final value = metadata(themeId, type, modifiers, language);
    if (value == 0x7FFFFFFF) return null;
    bool? flag(int use, int bit) => value & use != 0 ? value & bit != 0 : null;
    final colorMap = _theme(themeId)['tokenColorMap'] as List;
    return IdeTokenStyle(
      foreground: value & 0x10 != 0
          ? _color(colorMap[(value >> 15) & 0x1FF] as String)
          : null,
      italic: flag(0x01, 0x0800),
      bold: flag(0x02, 0x1000),
      underline: flag(0x04, 0x2000),
      strikethrough: flag(0x08, 0x4000),
    );
  }

  /// `#RRGGBB` or `#RRGGBBAA`.
  static Color _color(String hex) {
    final rgb = int.parse(hex.substring(1, 7), radix: 16);
    final alpha = hex.length == 9
        ? int.parse(hex.substring(7), radix: 16)
        : 255;
    return Color((alpha << 24) | rgb);
  }

  /// A theme of the fixture, loaded: bundled from assets/textmate, synthetic
  /// from the files the fixture holds.
  Future<ColorThemeData> loadTheme(String themeId) async {
    if (themeIds.contains(themeId)) {
      final manifest = TextMateManifest.parse(
        File('$textMateAssetRoot/manifest.json').readAsStringSync(),
      );
      final contribution = manifest.themeById(themeId)!;
      final theme = ColorThemeData.fromExtensionTheme(
        contribution,
        contribution.assetPath,
        extensionId: contribution.extensionId,
      );
      await theme.ensureLoaded(
        (path) => File('$textMateAssetRoot/$path').readAsString(),
      );
      return theme;
    }
    final spec = _theme(themeId);
    final files = (spec['files'] as Map).cast<String, String>();
    final path = spec['path'] as String;
    final theme = ColorThemeData.fromExtensionTheme(
      IThemeExtensionPoint(
        id: themeId,
        label: themeId,
        path: './$path',
        uiTheme: spec['uiTheme'] as String,
      ),
      '/synthetic/$path',
      extensionId: 'test.synthetic',
    );
    await theme.ensureLoaded(
      (location) async => files[location.substring('/synthetic/'.length)]!,
    );
    return theme;
  }
}
